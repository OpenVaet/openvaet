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

my $randomizationFile1 = 'public/doc/pfizer_trials/pfizer_trial_randomization_1.json';
my $randomizationFile2 = 'public/doc/pfizer_trials/pfizer_trial_randomization_2.json';

my %randomization1 = ();
my %randomization2 = ();

load_randomization_subjects_1();
load_randomization_subjects_2();

my $fromDate = "99999999";
my $toDate   = "0";
my %randomizations = ();
for my $subjectId (sort{$a <=> $b} keys %randomization1) {
	my $randomizationDate = $randomization1{$subjectId}->{'randomizationDate'} // die;
	$fromDate = $randomizationDate if $randomizationDate < $fromDate;
	$toDate = $randomizationDate if $randomizationDate > $toDate;
	unless (exists $randomization2{$subjectId}) {
		say "[$subjectId] is present in [1] but not in [2]";
	}
	$randomizations{$subjectId} = \%{$randomization1{$subjectId}};
}
for my $subjectId (sort{$a <=> $b} keys %randomization2) {
	my $randomizationDate = $randomization2{$subjectId}->{'randomizationDate'} // die;
	$fromDate = $randomizationDate if $randomizationDate < $fromDate;
	$toDate = $randomizationDate if $randomizationDate > $toDate;
	unless (exists $randomization1{$subjectId}) {
		say "[$subjectId] is present in [2] but not in [1]";
	}
	my $skipUpdate = 0;
	if (exists $randomizations{$subjectId}) {
		say $randomizations{$subjectId}->{'randomizationDate'} . " != " . $randomization2{$subjectId}->{'randomizationDate'} unless $randomizations{$subjectId}->{'randomizationDate'} == $randomization2{$subjectId}->{'randomizationDate'};
		for my $doseNum (sort{$a <=> $b} keys %{$randomizations{$subjectId}->{'doses'}}) {
			unless (exists $randomization2{$subjectId}->{'doses'}->{$doseNum}) {
				# p$randomizations{$subjectId}->{'doses'};
				# p$randomization2{$subjectId}->{'doses'};
				# say "subjectId : [$subjectId]";
				# die;
				$skipUpdate = 1;
			}
		}
	}
	if ($skipUpdate == 0) {
		$randomizations{$subjectId} = \%{$randomization2{$subjectId}};
	}
}
say "total subjects : " . keys %randomizations;
say "fromDate       : $fromDate";
say "toDate         : $toDate";

my $patientsToCutOff = 0;
my $patientsFromP1ToCutOff = 0;
for my $subjectId (sort{$a <=> $b} keys %randomizations) {
	my $randomizationDate = $randomizations{$subjectId}->{'randomizationDate'} // die;

	if ($randomizationDate <= '20201114') {
		$patientsToCutOff++;
	}
	if ($randomizationDate >= '20200720' && $randomizationDate <= '20201114') {
		$patientsFromP1ToCutOff++;
	}
}
say "patients to Nov. 14 2020 cut-off : [$patientsToCutOff]";
say "patients from July 20 to Nov. 14 2020 cut-off : [$patientsFromP1ToCutOff]";

open my $out, '>:utf8', 'public/doc/pfizer_trials/pfizer_trial_randomizations_merged.json';
print $out encode_json\%randomizations;
close $out;

sub load_randomization_subjects_1 {
	open my $in, '<:utf8', $randomizationFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization1 = %$json;
}

sub load_randomization_subjects_2 {
	open my $in, '<:utf8', $randomizationFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization2 = %$json;
}