#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use JSON;
use Proc::Background;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;


my %dates         = ();
my $threadsOnBulk = 6;
my $totalDates    = 0;

die unless -d "raw_data/libramemoria";

list_dates();

sub list_dates {
	my $fromDatetime  = '2007-01-01 12:00:00';
	my $toDatetime    = time::current_datetime();
	($toDatetime)     = split ' ', $toDatetime;
	$toDatetime       = "$toDatetime 12:00:00";
	my $fromTimestamp = time::datetime_to_timestamp($fromDatetime);
	my $toTimestamp   = time::datetime_to_timestamp($toDatetime);
	my $totalFound    = 0;
	while ($fromTimestamp <= $toTimestamp) {
		my ($date)      = split ' ', $fromDatetime;
		my $dailyFile   = "raw_data/libramemoria/libramemoria_" . "$date.json";
		my $knownDeaths = 0;
		unless (-f $dailyFile) {
			$totalDates++;
			$dates{$fromTimestamp} = $date;
		}
		$fromDatetime     = time::add_seconds_to_datetime($fromDatetime, 86400);
		$fromTimestamp    = time::datetime_to_timestamp($fromDatetime);
	}
}

# p%dates;
my %threads = (); # Keeps track of the threads initiated.
my ($threadsFinished, $threadsInitiated, $totalThreads) = (0, 0, 0);
$totalThreads = keys %dates;
while ($threadsFinished < $totalThreads) {
	my $currentDatetime = time::current_datetime();
	STDOUT->printflush("\r$currentDatetime - Monitoring sub-threads [$threadsFinished / $totalThreads]");
	while ($threadsInitiated < $threadsOnBulk) {
		for my $timestamp (sort{$a <=> $b} keys %dates) {
			unless (exists $threads{$timestamp}->{'initiated'}) {
				my $date = $dates{$timestamp} // die;
				my $currentDatetime = time::current_datetime();
				# say "$currentDatetime - Starting [$date]";
				$threadsInitiated++;
				my $thread = Proc::Background->new('perl', 'tasks/studies/french_press/get_libramemoria_date.pl', $date) || die "failed";
				$threads{$timestamp}->{'thread'} = $thread;
				$threads{$timestamp}->{'initiated'} = 1;
				# say "date : $date";
				# say "firstId : $firstId";
				# say "lastId  : $lastId";
				sleep 2;
			}
			last if $threadsInitiated == $threadsOnBulk;
		}
	}
	for my $timestamp (keys %threads) {
		next if exists $threads{$timestamp}->{'finished'};
		my $thread = $threads{$timestamp}->{'thread'} // die;
		unless ($thread->alive) {
			my $date = $dates{$timestamp} // die;
			$threads{$timestamp}->{'finished'} = 1;
			$threadsFinished++;
			$threadsInitiated--;
			my $dailyFile  = "raw_data/libramemoria/libramemoria_" . "$date.json";
			die "failed with date [$date]" unless -f $dailyFile;
		}
	}
	sleep 1;
}
my $currentDatetime = time::current_datetime();
STDOUT->printflush("\r$currentDatetime - Monitoring sub-threads [$threadsFinished / $totalThreads]");
