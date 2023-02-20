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

my $adverseFile       = "public/doc/pfizer_trials/pfizer_adfacevd_patients.json";
my $randomizationFile = "public/doc/pfizer_trials/pfizer_trial_randomizations_merged.json";
my $allFilesFile      = "public/doc/pfizer_trials/pfizer_sas_data_patients.json";
my $addvFile          = "public/doc/pfizer_trials/pfizer_addv_patients.json";
my $advaFile          = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my %advaData = ();
my %addvData = ();
my %randomizationData = ();
my %allFilesData      = ();
my %adverseData       = ();
adverse_data();        # Loads the JSON formatted adverse effects data.
randomization_data();  # Loads the JSON formatted randomization data.
all_files_data();      # Loads the JSON formatted files summary data.
adva_data();
addv_data();

sub adverse_data {
	my $json;
	open my $in, '<:utf8', $adverseFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adverseData = %$json;
	say "[$adverseFile] -> subjects : " . keys %adverseData;
}

sub randomization_data {
	my $json;
	open my $in, '<:utf8', $randomizationFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomizationData = %$json;
	say "[$randomizationFile] -> subjects : " . keys %randomizationData;
}

sub all_files_data {
	my $json;
	open my $in, '<:utf8', $allFilesFile;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%allFilesData = %$json;
	say "[$allFilesFile] -> subjects : " . keys %{$allFilesData{'subjects'}};
}

sub adva_data {
	open my $in, '<:utf8', $advaFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
}

sub addv_data {
	open my $in, '<:utf8', $addvFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%addvData = %$json;
}

my %stats = ();
my %subjects = ();
for my $subjectId (sort keys %advaData) {
	$stats{'totalPatients'}++;
	my $trialSiteId   = $advaData{$subjectId}->{'trialSiteId'} // die;
	my $uSubjectId    = $advaData{$subjectId}->{'uSubjectId'} // die;
	die unless exists $allFilesData{'subjects'}->{$subjectId};
	# 1st Dose.
	my $dose1Datetime = $advaData{$subjectId}->{'dose1Datetime'} // die;
	my ($dose1Date)   = split ' ', $dose1Datetime;
	my $dose1CompDate = $dose1Date;
	$dose1CompDate    =~ s/\D//g;

	next unless $dose1CompDate <= 20201114;
	$stats{'totalPatientsWithDose1Nov14'}->{'total'}++;
	unless (exists $randomizationData{$subjectId}) {
		$stats{'totalPatientsWithDose1Nov14'}->{'notInRandomizationFile'}++;
		$subjects{$subjectId}->{'randomizationDate'} = $dose1CompDate;
		$subjects{$subjectId}->{'randomizationDateOrigin'} = 'Approximative based on dose 1 date';
	} else {
		my $randomizationDate = $randomizationData{$subjectId}->{'randomizationDate'} // die;
		$subjects{$subjectId}->{'randomizationDate'} = $randomizationDate;
		$subjects{$subjectId}->{'randomizationDateOrigin'} = 'Randomization file';
	}
	
	# Attributed group.
	my $phase = $advaData{$subjectId}->{'phase'} // die;
	die unless
		$phase eq "Phase 1" ||
		$phase eq "Phase 3" ||
		$phase eq "Phase 2_ds360/ds6000" ||
		$phase eq "Phase 3_ds6000";
	if ($phase eq "Phase 1") {
		$stats{'totalPatientsWithDose1Nov14'}->{'totalPatientsPhase1'}++;
		next;
	}

	# November stats.
	$stats{'totalPatientsNotPhase1WithDose1Nov14'}->{'total'}++;
	my $actArm = $advaData{$subjectId}->{'actArm'} // die;
	if ($actArm eq 'Not Treated') {
		$stats{'totalPatientsNotPhase1WithDose1Nov14'}->{'totalPatientsArmGroupNotTreated'}++;
		next;
	}
	$stats{'totalPatientsNotPhase1WithArmGroupWithDose1Nov14'}->{'total'}++;
	$stats{'totalPatientsNotPhase1WithArmGroupWithDose1Nov14'}->{$actArm}++;

	# Exclusions.
	unless (exists $randomizationData{$subjectId}) {
		if (exists $addvData{$subjectId}) {
			# p$advaData{$subjectId};
			# p$addvData{$subjectId};
			$stats{'totalPatientsNotPhase1WithArmGroupWithDose1Nov14'}->{'notInRandomizationFileButHasExlusion'}++;
			next;
		}
		# p$advaData{$subjectId};
		# p$allFilesData{'subjects'}->{$subjectId};
		# p$addvData{$subjectId};
		$stats{'totalPatientsNotPhase1WithArmGroupWithDose1Nov14'}->{'notInRandomizationFileAndNoExlusion'}->{'total'}++;
		$stats{'totalPatientsNotPhase1WithArmGroupWithDose1Nov14'}->{'notInRandomizationFileAndNoExlusion'}->{$actArm}++;
		p$adverseData{$subjectId};
		say "subjectId             : $subjectId";
		# die if exists $adverseData{$subjectId};
	}

	# 2nd Dose.
	my $dose2Datetime = $advaData{$subjectId}->{'dose2Datetime'} // next;
	my ($dose2Date)   = split ' ', $dose2Datetime;
	my $dose2CompDate = $dose2Date;
	$dose2CompDate    =~ s/\D//g;
	next unless $dose2CompDate <= 20201107;
	$stats{'totalPatientsWithDose2Nov07'}->{'total'}++;
	$stats{'totalPatientsWithDose2Nov07'}->{$actArm}++;
	# next unless $dose2Date && ($dose2Date <= 20201114); # Fernando's 2 doses in efficacy
}

# Verifying randomization dates.
for my $subjectId (sort{$a <=> $b} keys %randomizationData) {
	my $randomizationDate = $randomizationData{$subjectId}->{'randomizationDate'} // die;
	next unless $randomizationDate <= 20201114;
	next if exists $subjects{$subjectId};
	$subjects{$subjectId}->{'randomizationDate'} = $randomizationDate;
	$subjects{$subjectId}->{'randomizationDateOrigin'} = 'Randomization file only';
}

for my $subjectId (sort{$a <=> $b} keys %subjects) {
	my $randomizationDate = $subjects{$subjectId}->{'randomizationDate'} // die;
	if ($randomizationDate >= 20200720) {

		$stats{'totalPatientsWithDose1July20ToNov14'}->{'total'}++;
		unless (exists $randomizationData{$subjectId}) {
			# p$advaData{$subjectId};
			$stats{'totalPatientsWithDose1July20ToNov14'}->{'notInRandomizationFile'}++;
		} else {
			unless (exists $advaData{$subjectId}) {
				$stats{'totalPatientsWithDose1July20ToNov14'}->{'notInAdvaFile'}++;
			}
		}
	}
}

p%stats;

say "Total with randomization date : " . keys %subjects;

open my $out, '>:utf8', 'public/doc/pfizer_trials/subjects_randomization_dates_merged.json';
print $out encode_json\%subjects;
close $out;