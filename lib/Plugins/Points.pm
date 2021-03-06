package SimpleBot::Plugin::Points;

##
# Points.pm
# SimpleBot Plugin
# Copyright (c) 2013 Joseph Huckaby
# MIT Licensed
#
# !award jhuckaby +50
# !deduct jhuckaby 50
# !scores (10)
##

use strict;
use FileHandle;
use base qw( SimpleBot::Plugin );
use Tools;

sub init {
	my $self = shift;
	$self->register_commands('award', 'deduct', 'scores', 'points');
}

sub points {
	# umbrella command for all the other commands
	my ($self, $cmd, $args) = @_;
	my $username = $args->{who};
	
	if ($cmd =~ /^(\w+)(.*)$/) {
		my ($sub_cmd, $value) = ($1, $2);
		$value = trim($value);
		if ($self->can($sub_cmd)) { return $self->$sub_cmd($value, $args); }
		else { return "$username: Unknown points command: $sub_cmd"; }
	}
	
	return undef;
}

sub award {
	# award points to a user
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($msg =~ /^(\w+)\s+(.+)$/) {
		my ($target_nick, $amount) = ($1, $2);
		$amount = trim($amount);
		my $action = 'award';
		
		my $force = 0;
		if ($amount =~ s/\s+force$//i) { $force = 1; }
		$amount =~ s/\s+(points?|pts?)//i;
		
		my $reason = '';
		if ($amount =~ s/\s+(.+)$//) {
			$reason = trim($1); 
			$reason =~ s/\W$//;
			if ($reason !~ /^(for|because|bcuz|bc)\s+/i) { $reason = 'for ' . $reason; }
			$reason = ' ' . $reason;
		}
		
		# support alternate syntax (swapped amount and username)
		if (($amount !~ /^(\+|\-)?\d+$/) && ($target_nick =~ /^(\+|\-)?\d+$/)) {
			my $temp = $amount; $amount = $target_nick; $target_nick = $temp;
		}
		
		if ($amount !~ /^(\+|\-)?\d+$/) { return "$username: Invalid syntax, please specify a number of points to award or deduct."; }
		if ($amount =~ /^\-(\d+)$/) { $amount = 0 - int($1); $action = 'deduct'; }
		if (!$amount) { return "$username: Whatever."; }
		
		# setup user list
		$self->{data}->{users} ||= {};
		my $users = $self->{data}->{users};
		
		# validate nick
		my $eb_channel = $self->{bot}->{_eb_channels}->{ sch(lc($chan)) } || {};
		if (!$eb_channel->{lc($target_nick)} && !$users->{lc($target_nick)} && !$force) {
			return "$username: Cannot give points to unknown nick '$target_nick' (unless you use force).";
		}
		if ((lc($target_nick) eq lc($username)) && ($amount > 0) && !$force) {
			return "$username: You cannot give points to yourself, cheater.";
		}
				
		# find old rank
		my $old_user_rank = $self->find_rank( lc($target_nick) );
		
		# make change
		$users->{ lc($target_nick) } += int($amount);
		if ($users->{ lc($target_nick) } < 1) {
			delete $users->{ lc($target_nick) };
		}
		$self->dirty(1);
		
		my $abs_amount = $amount; $abs_amount =~ s/\D+//g;
		my $new_user_total = $users->{ lc($target_nick) } || 0;
		
		# find new rank
		my $new_user_rank = $self->find_rank( lc($target_nick) );
		
		# compose extra text
		my $extra = "  Their new score is $new_user_total points.";
		if ($new_user_rank < $old_user_rank) {
			$extra .= "  This bumps them up to rank \#$new_user_rank.";
		}
		elsif ($new_user_rank > $old_user_rank) {
			$extra .= "  This brings them down to rank \#$new_user_rank.";
		}
		
		$self->say(
			channel => nch($chan), 
			body => ($action eq 'award') ?
				"$username awarded $amount points to $target_nick$reason.$extra" :
				"$username deducted $abs_amount points from $target_nick$reason.$extra"
		);
		
		my $fh = new FileHandle ">>logs/points.log";
		my $now = time();
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($now);
		my $nice_date = sprintf("%0004d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
		my $line = '[' . join('][', 
			$now,
			$nice_date,
			$username,
			$action,
			$target_nick,
			$amount,
			trim($reason)
		) . "]\n";
		$fh->print( $line );
		$fh->close();
	}
	else { return "$username: Invalid syntax, please use: !award NICKNAME POINTS"; }
	
	return undef;
}

sub deduct {
	# deduct points from a user
	my ($self, $msg, $args) = @_;
	my $username = $args->{who};
	
	if ($msg =~ /^(\w+)\s+(\+|\-)?(\d+)(.*)$/) {
		my ($target_nick, $direction, $amount, $after) = ($1, $2, $3, $4);
		$amount = 0 - int($amount);
		return $self->award( "$target_nick $amount $after", $args );
	}
	elsif ($msg =~ /^(\+|\-)?(\d+)\s+(\w+)(.*)$/) {
		my ($direction, $amount, $target_nick, $after) = ($1, $2, $3, $4);
		$amount = 0 - int($amount);
		return $self->award( "$target_nick $amount $after", $args );
	}
	else { return "$username: Invalid syntax, please use: !deduct NICKNAME POINTS"; }
}

sub scores {
	# show scoreboard
	my ($self, $max, $args) = @_;
	my $username = $args->{who};
	my $chan = $args->{channel};
	
	if ($max =~ /^(\w+)\s+(\+|\-)?(\d+)(.*)$/) {
		my ($target_nick, $direction, $amount, $after) = ($1, $2, $3, $4);
		return $self->award( "$target_nick $direction$amount $after", $args );
	}
	
	my $users = $self->{data}->{users} ||= {};
	if (!scalar keys %$users) { return "$username: No points have been awarded."; }
	
	if ($max =~ /clear/i) {
		$self->{data}->{users} = {};
		$self->dirty(1);
		return "$username: The score list has been cleared.";
	}
	
	if (($max !~ /^\d+$/) || !$max) { $max = 10; }
	
	my $body = "Top $max Scores:\n";
	my $idx = 1;
	foreach my $target_nick (reverse sort { $users->{$a} <=> $users->{$b} } keys %$users) {
		my $points = $users->{$target_nick} || 0;
		$body .= "$idx. $target_nick: $points points\n";
		$idx++; if ($idx > $max) { last; }
	}
	$self->say( channel => nch($chan), body => $body );
	
	return undef;
}

sub nick_change {
	# called when a user nick changes
	my ($self, $args) = @_;
	
	my $old_nick = lc($args->{old_nick}); $old_nick =~ s@\[.+\]@@g;
	my $new_nick = lc($args->{new_nick}); $new_nick =~ s@\[.+\]@@g;
	
	my $users = $self->{data}->{users} ||= {};
	
	# JH 2014-02-15 No longer tracking users who become 'Unidentified...'
	if ($users->{ $old_nick } && !$users->{ $new_nick } && ($new_nick !~ /^unidentified/i)) {
		my $points = $users->{ $old_nick };
		delete $users->{ $old_nick };
		$users->{ $new_nick } = $points;
		$self->dirty(1);
	}
}

sub find_rank {
	# find score rank given username
	my ($self, $nick) = @_;
	my $users = $self->{data}->{users} ||= {};
	
	my $idx = 1;
	foreach my $target_nick (reverse sort { $users->{$a} <=> $users->{$b} } keys %$users) {
		if (lc($target_nick) eq lc($nick)) { return $idx; }
		$idx++;
	}
	
	return $idx;
}

1;
