#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use time;

my $bnt      = 'tasks/pfizer_trials/j_r/retsev_bnt_list.csv';
my $placebo  = 'tasks/pfizer_trials/j_r/retsev_placebo_list.csv';

my %subjects = ();

load_bnt();
load_placebo();

sub load_bnt {
	open my $in, '<:utf8', $bnt;
	while (<$in>) {
		chomp $_;
		$subjects{$_}->{'BNT'} = 1;
	}
	close $in;
}

sub load_placebo {
	open my $in, '<:utf8', $placebo;
	while (<$in>) {
		chomp $_;
		$subjects{$_}->{'Placebo'} = 1;
	}
	close $in;
}

open my $out, '>:utf8', 'tasks/pfizer_trials/j_r/retsef_sae.csv';
say $out "subjectId;saeAsPlacebo;saeAsBNT;";
for my $subjectId (sort{$a <=> $b} keys %subjects) {
	my $saeAsPlacebo = 0;
	my $saeAsBNT = 0;
	$saeAsBNT = 1 if exists $subjects{$subjectId}->{'BNT'};
	$saeAsPlacebo = 1 if exists $subjects{$subjectId}->{'Placebo'};
	say $out "$subjectId;$saeAsPlacebo;$saeAsBNT;";
}
close $out;