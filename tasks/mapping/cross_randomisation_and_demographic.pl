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

my $dataFolder        = "raw_data/pfizer_trials/randomization_scheme_output";
my $randomizationFile = "raw_data/pfizer_trials/randomization_scheme_output/pfizer_trial_randomization.json";
my $trialSubjectsFile = "raw_data/pfizer_trials/demographic_output/pfizer_trial_subjects.json";

my %randomizationData = ();
my %trialSubjectsData = ();
randomization_data(); # Loads the JSON formatted randomization data.
subjects_data();      # Loads the JSON formatted trial subjects data.

my $missing = 0;
for my $patientId (sort keys %randomizationData) {
	unless (exists $trialSubjectsData{$patientId}) {
		p$randomizationData{$patientId};
		say "patientId : [$patientId]";
		$missing++;
	}
}
say "missing : [$missing]";


sub randomization_data {
	my $json;
	open my $in, '<:utf8', $randomizationFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomizationData = %$json;
}

sub subjects_data {
	my $json;
	open my $in, '<:utf8', $trialSubjectsFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%trialSubjectsData = %$json;
}