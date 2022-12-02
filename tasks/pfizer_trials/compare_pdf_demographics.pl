#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $demographicFile1 = 'public/doc/pfizer_trials/pfizer_trial_demographics_1.json';
my $demographicFile2 = 'public/doc/pfizer_trials/pfizer_trial_demographics_2.json';

my %demographic1 = ();
my %demographic2 = ();

load_demographic_subjects_1();
load_demographic_subjects_2();

my $fromDate = "99999999";
my $toDate   = "0";
my %demographics = ();
for my $subjectId (sort{$a <=> $b} keys %demographic1) {
	my $screeningDate = $demographic1{$subjectId}->{'screeningDate'} // die;
	$fromDate = $screeningDate if $screeningDate < $fromDate;
	$toDate = $screeningDate if $screeningDate > $toDate;
	unless (exists $demographic2{$subjectId}) {
		say "[$subjectId] is present in [1] but not in [2]";
	}
	$demographics{$subjectId} = \%{$demographic1{$subjectId}};
}
for my $subjectId (sort{$a <=> $b} keys %demographic2) {
	my $screeningDate = $demographic2{$subjectId}->{'screeningDate'} // die;
	$fromDate = $screeningDate if $screeningDate < $fromDate;
	$toDate = $screeningDate if $screeningDate > $toDate;
	unless (exists $demographic1{$subjectId}) {
		say "[$subjectId] is present in [2] but not in [1]";
	}
	if (exists $demographics{$subjectId}) {
		die unless $demographics{$subjectId}->{'screeningDate'} == $demographic2{$subjectId}->{'screeningDate'};
	}
	$demographics{$subjectId} = \%{$demographic2{$subjectId}};
}
say "total subjects : " . keys %demographics;
say "fromDate       : $fromDate";
say "toDate         : $toDate";

open my $out, '>:utf8', 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
print $out encode_json\%demographics;
close $out;

sub load_demographic_subjects_1 {
	open my $in, '<:utf8', $demographicFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographic1 = %$json;
}

sub load_demographic_subjects_2 {
	open my $in, '<:utf8', $demographicFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographic2 = %$json;
}