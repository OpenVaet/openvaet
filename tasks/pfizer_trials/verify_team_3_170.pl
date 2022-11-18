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

my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomization.json";
my $trialSubjectsFile = "public/doc/pfizer_trials/pfizer_trial_demographics.json";
my $file1             = 'public/doc/pfizer_trials/pfizer_trial_efficacy_cases.json';
my $srcFile           = 'raw_data/pfizer_trials/170-Efficacy-Population-Analysis-19-23-days-protocol-deviaition-chart-26-Sep-2022-Final.csv';
my %srcData           = ();
my %file1Data         = ();

load_source();
load_file_1();
calc_tot();

sub load_source {


	# We load the file produced by the daily clout.
	my %stats       = ();
	my $patientsNum = 0;
	open my $in, '<:utf8', $srcFile;
	while (<$in>) {
		chomp $_;
		my (undef, $subjectId, $countryData) = split ';', $_;
		next unless $subjectId;
		$patientsNum++;
		$srcData{$subjectId} = 1;
	}
	close $in;
	# p%srcData;
	say "[$srcFile] -> patients : " . keys %srcData;
}

sub calc_tot {
	my %allIds    = ();
	for my $subjectId (sort keys %file1Data) {
		$allIds{$subjectId} = 1;
		say "missing in src subjectId : $subjectId" unless exists $srcData{$subjectId};
	}
	for my $subjectId (sort keys %srcData) {
		say "missing in pfi subjectId : $subjectId" unless exists $allIds{$subjectId};
		$allIds{$subjectId} = 1;
	}
	say "[total] -> patients : " . keys %allIds;
}

sub load_file_1 {
	my $json;
	open my $in, '<:utf8', $file1;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%file1Data = %$json;
	say "[$file1] -> patients : " . keys %file1Data;
}