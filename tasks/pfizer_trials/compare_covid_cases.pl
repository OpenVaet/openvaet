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

my $caseFile1 = 'public/doc/pfizer_trials/pfizer_trial_cases_1.json';
my $caseFile2 = 'public/doc/pfizer_trials/pfizer_trial_positive_cases_april_2021.json';

my %case1 = ();
my %case2 = ();

load_case_subjects_1();
load_case_subjects_2();

my %cases = ();
# Increments manually the only missing case from file 1 to file 2 as we are getting lazy...
$cases{'10081302'}->{'swabDate'} = '20201007';
$cases{'10081302'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'10081302'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'10081302'}->{'nucleicAcidAmplificationTest2'} = 'Pos';
$cases{'10081302'}->{'sourceTable'} = '16.2.8.5';
$cases{'10081302'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'10931063'}->{'swabDate'} = '20201028';
$cases{'10931063'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'10931063'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'10931063'}->{'nucleicAcidAmplificationTest2'} = 'Neg';
$cases{'10931063'}->{'sourceTable'} = '16.2.8.5';
$cases{'10931063'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'10931122'}->{'swabDate'} = '20201008';
$cases{'10931122'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'10931122'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'10931122'}->{'nucleicAcidAmplificationTest2'} = 'Neg';
$cases{'10931122'}->{'sourceTable'} = '16.2.8.5';
$cases{'10931122'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11101229'}->{'swabDate'} = '20201006';
$cases{'11101229'}->{'visit1NBindingAssayTest'}       = 'Pos';
$cases{'11101229'}->{'nucleicAcidAmplificationTest1'} = 'Pos';
$cases{'11101229'}->{'nucleicAcidAmplificationTest2'} = 'Unk';
$cases{'11101229'}->{'sourceTable'} = '16.2.8.5';
$cases{'11101229'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11231171'}->{'swabDate'} = '20201102';
$cases{'11231171'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'11231171'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'11231171'}->{'nucleicAcidAmplificationTest2'} = 'Neg';
$cases{'11231171'}->{'sourceTable'} = '16.2.8.5';
$cases{'11231171'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11331512'}->{'swabDate'} = '20201011';
$cases{'11331512'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'11331512'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'11331512'}->{'nucleicAcidAmplificationTest2'} = 'Unk';
$cases{'11331512'}->{'sourceTable'} = '16.2.8.5';
$cases{'11331512'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11471037'}->{'swabDate'} = '20200813';
$cases{'11471037'}->{'visit1NBindingAssayTest'}       = 'Unk';
$cases{'11471037'}->{'nucleicAcidAmplificationTest1'} = 'Pos';
$cases{'11471037'}->{'nucleicAcidAmplificationTest2'} = 'Pos';
$cases{'11471037'}->{'sourceTable'} = '16.2.8.5';
$cases{'11471037'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11681226'}->{'swabDate'} = '20201019';
$cases{'11681226'}->{'visit1NBindingAssayTest'}       = 'Pos';
$cases{'11681226'}->{'nucleicAcidAmplificationTest1'} = 'Pos';
$cases{'11681226'}->{'nucleicAcidAmplificationTest2'} = 'Unk';
$cases{'11681226'}->{'sourceTable'} = '16.2.8.5';
$cases{'11681226'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'11781118'}->{'swabDate'} = '20200929';
$cases{'11781118'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'11781118'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'11781118'}->{'nucleicAcidAmplificationTest2'} = 'Pos';
$cases{'11781118'}->{'sourceTable'} = '16.2.8.5';
$cases{'11781118'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'12262108'}->{'swabDate'} = '20201027';
$cases{'12262108'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'12262108'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'12262108'}->{'nucleicAcidAmplificationTest2'} = 'Unk';
$cases{'12262108'}->{'sourceTable'} = '16.2.8.5';
$cases{'12262108'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'12262235'}->{'swabDate'} = '20201105';
$cases{'12262235'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'12262235'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'12262235'}->{'nucleicAcidAmplificationTest2'} = 'Unk';
$cases{'12262235'}->{'sourceTable'} = '16.2.8.5';
$cases{'12262235'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
$cases{'44441043'}->{'swabDate'} = '20201004';
$cases{'44441043'}->{'visit1NBindingAssayTest'}       = 'Neg';
$cases{'44441043'}->{'nucleicAcidAmplificationTest1'} = 'Neg';
$cases{'44441043'}->{'nucleicAcidAmplificationTest2'} = 'Neg';
$cases{'44441043'}->{'sourceTable'} = '16.2.8.5';
$cases{'44441043'}->{'sourceFile'} = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
for my $subjectId (sort{$a <=> $b} keys %case1) {
	unless (exists $case2{$subjectId}) {
		say "[$subjectId] is present in [1] but not in [2]";
	}
	$cases{$subjectId} = \%{$case2{$subjectId}};
}
for my $subjectId (sort{$a <=> $b} keys %case2) {
	unless (exists $cases{$subjectId}) {
		say "[$subjectId] is present in [2] but not in [1]";
	}
	my $fileToIncrement = 0;
	unless (exists $cases{$subjectId}) {
		$fileToIncrement = 1;
	}
	$cases{$subjectId} = \%{$case2{$subjectId}};
	if ($fileToIncrement) {
		$cases{$subjectId}->{'sourceTable'} = '16.2.8.1';
		$cases{$subjectId}->{'sourceFile'}  = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements.pdf';
	} else {
		$cases{$subjectId}->{'sourceTable'} = '16.2.8.1';
		$cases{$subjectId}->{'sourceFile'}  = 'pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-lab-measurements-sensitive.pdf';
	}
}
# die;
# p%cases;
say "total subjects : " . keys %cases;

open my $out, '>:utf8', 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
print $out encode_json\%cases;
close $out;

sub load_case_subjects_1 {
	open my $in, '<:utf8', $caseFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%case1 = %$json;
	say "[$caseFile1] -> patients : " . keys %case1;
}

sub load_case_subjects_2 {
	open my $in, '<:utf8', $caseFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%case2 = %$json;
	say "[$caseFile2] -> patients : " . keys %case2;
}