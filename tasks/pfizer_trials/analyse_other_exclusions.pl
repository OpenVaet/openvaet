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
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);

my $exclusionsFile = 'public/doc/pfizer_trials/pfizer_other_exclusions_subjects.json';
my $deviationsFile = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $pcrTestsFile   = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $symptomsFile   = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';

my %exclusions = ();
my %deviations = ();
my %pcrTests   = ();
my %symptoms   = ();

load_exclusions();
load_deviations();
load_pcr_tests();
load_symptoms();

# p%deviations;

my %stats = ();
my $excludedWithPositivePCR = 0;
for my $subjectId (sort{$a <=> $b} keys %exclusions) {
	my ($totalDeviations, $totalImportantDeviations) = (0, 0);
	for my $deviationDate (sort keys %{$deviations{$subjectId}}) {
		my $compdate = $deviationDate;
		$compdate =~ s/\D//g;
		next unless $compdate <= 20201114;
		my $deviationCategory = $deviations{$subjectId}->{$deviationDate}->{'dvCat'} // die;
		$totalImportantDeviations++ if $deviationCategory eq 'Non-Important';
		$totalDeviations++;
	}
	my $arm = $exclusions{$subjectId}->{'arm'} // die;
	# p$exclusions{$subjectId};
	# p$pcrTests{$subjectId};
	# die;
	# unless (exists $deviations{$subjectId}) {
	# 	p$exclusions{$subjectId};
	# 	p$deviations{$subjectId};
	# 	p$pcrTests{$subjectId};
	# 	die;
	# }
	say "subjectId                : $subjectId";
	say "arm                      : $arm";
	my ($totalPositivePCRs, $totalPCRs) = (0, 0);
	for my $visitDate (sort keys %{$pcrTests{$subjectId}->{'mbVisits'}}) {
		next unless exists $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $compdate = $visitDate;
		$compdate =~ s/\D//g;
		next unless $compdate <= 20201114;
		my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		$totalPCRs++;
		$totalPositivePCRs++ if $pcrResult eq 'POS';
		say "visitDate                : $visitDate";
		say "pcrResult                : $pcrResult";
	}
	say "totalDeviations          : $totalDeviations";
	say "totalImportantDeviations : $totalImportantDeviations";
	say "totalPositivePCRs        : $totalPositivePCRs";
	say "totalPCRs                : $totalPCRs";
	p$deviations{$subjectId};
	p$symptoms{$subjectId};
	say "*" x 50;
	say "*" x 50;
	$stats{'totalByArms'}->{$arm}++;
	$stats{'excludedWithPCRPositive'}->{$arm}++ if $totalPositivePCRs;
	$stats{'excludedWithImportantDeviation'}->{$arm}++ if $totalImportantDeviations;
	$stats{'excludedWithDeviation'}->{$arm}++ if $totalDeviations;
	$excludedWithPositivePCR++ if $totalPositivePCRs;
}
say "excludedWithPositivePCR : $excludedWithPositivePCR";
p%stats;

sub load_exclusions {
	open my $in, '<:utf8', $exclusionsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%exclusions = %$json;
	say "[$exclusionsFile] -> subjects : " . keys %exclusions;
}

sub load_deviations {
	open my $in, '<:utf8', $deviationsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%deviations = %$json;
	say "[$deviationsFile] -> subjects : " . keys %deviations;
}

sub load_pcr_tests {
	open my $in, '<:utf8', $pcrTestsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pcrTests = %$json;
	say "[$pcrTestsFile] -> subjects : " . keys %pcrTests;
}

sub load_symptoms {
	open my $in, '<:utf8', $symptomsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%symptoms = %$json;
	say "[$symptomsFile] -> subjects : " . keys %symptoms;
}