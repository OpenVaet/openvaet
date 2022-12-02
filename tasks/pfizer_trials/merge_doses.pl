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

my $advaFile           = 'public/doc/pfizer_trials/pfizer_adva_patients.json';
my $randomizationFile1 = 'public/doc/pfizer_trials/pfizer_trial_randomization_1.json';
my $randomizationFile2 = 'public/doc/pfizer_trials/pfizer_trial_randomization_2.json';

my %adva               = ();
my %randomization      = ();

load_adva();
load_randomization_1();
load_randomization_2();
verify_doses();

my %stats      = ();
my %dosesDates = ();
for my $subjectId (sort{$a <=> $b} keys %adva) {
	my ($dose1, $dose1Date, $dose2, $dose2Date, $doseDateOrigin);
	unless (exists $randomization{$subjectId}) {
		my $dose1Datetime = $adva{$subjectId}->{'dose1Datetime'};
		my $dose2Datetime = $adva{$subjectId}->{'dose2Datetime'};
		my $actArm = $adva{$subjectId}->{'actArm'} // die;
		$dose1Date = convert_date($dose1Datetime);
		if ($dose2Datetime) {
			$dose2Date = convert_date($dose2Datetime);
		}
		if ($actArm =~ /BNT162b\d/) {
			($dose1) = $actArm =~ /(BNT162b\d)/;
			$dose2 = $dose1;
		} else {
			die unless $actArm eq 'Placebo';
			$dose1 = $actArm;
			$dose2 = $dose1;
		}
		$doseDateOrigin = 'Adva only';
		# p$randomization{$subjectId};
		# say "dose1Date : $dose1Date";
		# say "dose2Date : $dose2Date";
		# die;
		# p$adva{$subjectId};
		# die;
		$stats{'noRandomizationData'}++;
	} else {
		# p$adva{$subjectId};
		$dose1 = $randomization{$subjectId}->{'doses'}->{'1'}->{'dose'};
		$dose2 = $randomization{$subjectId}->{'doses'}->{'2'}->{'dose'};
		$dose1Date = $randomization{$subjectId}->{'doses'}->{'1'}->{'doseDate'};
		$dose2Date = $randomization{$subjectId}->{'doses'}->{'2'}->{'doseDate'};
		$doseDateOrigin = 'Adva & Randomization';

		# Verifying vaccination dates based on ADVA if any.
		if ($dose1Date) {
			unless ($randomization{$subjectId}->{'doses'}->{'1'}->{'doseDate'} eq $dose1Date) {
				# p$randomization{$subjectId};
				# p$adva{$subjectId};
				# say "subjectId     : $subjectId";
				die $randomization{$subjectId}->{'doses'}->{'1'}->{'doseDate'} . " ne $dose1Date";
			}
		}
		if ($dose2Date) {
			unless ($randomization{$subjectId}->{'doses'}->{'2'}->{'doseDate'} eq $dose2Date) {
				# p$randomization{$subjectId};
				# p$adva{$subjectId};
				# say "subjectId     : $subjectId";
				die $randomization{$subjectId}->{'doses'}->{'2'}->{'doseDate'} . " ne $dose2Date";
			}
		}
		unless ($dose1) {
			if ($adva{$subjectId}->{'dose1Datetime'} || $dose1Date) {
				if ($dose1Date) {
					$dose1 = $randomization{$subjectId}->{'randomizationGroup'} // die;
				} else {
					my $dose1Datetime = $adva{$subjectId}->{'dose1Datetime'} // die;
					my $actArm = $adva{$subjectId}->{'actArm'} // die;
					if ($actArm ne 'Not Treated') {
						$dose1Date = convert_date($dose1Datetime);
						if ($actArm =~ /BNT162b\d/) {
							($dose1) = $actArm =~ /(BNT162b\d)/;
						} else {
							die "actArm : $actArm" unless $actArm eq 'Placebo';
							$dose1 = $actArm;
						}
					}
				}
			}
			# p$adva{$subjectId};
			# p$randomization{$subjectId};
			# die unless $dose1;
		}
		unless ($dose2) {
			if ($adva{$subjectId}->{'dose2Datetime'} || $dose2Date) {
				if ($dose2Date) {
					$dose2 = $randomization{$subjectId}->{'randomizationGroup'} // die;
				} else {
					my $dose2Datetime = $adva{$subjectId}->{'dose2Datetime'} // die;
					my $actArm = $adva{$subjectId}->{'actArm'} // die;
					if ($actArm ne 'Not Treated') {
						$dose2Date = convert_date($dose2Datetime);
						if ($actArm =~ /BNT162b\d/) {
							($dose2) = $actArm =~ /(BNT162b\d)/;
						} else {
							die unless $actArm eq 'Placebo';
							$dose2 = $actArm;
						}
					}
				}
			}
		}
		# say "dose1Datetime : $dose1Datetime";
		# say "dose2Datetime : $dose2Datetime";
		# say "subjectId     : $subjectId";
		# die;
	}
	$dosesDates{$subjectId}->{'doseDateOrigin'} = $doseDateOrigin;
	$dosesDates{$subjectId}->{'dose1'} = $dose1;
	$dosesDates{$subjectId}->{'dose2'} = $dose2;
	$dosesDates{$subjectId}->{'dose1Date'} = $dose1Date;
	$dosesDates{$subjectId}->{'dose2Date'} = $dose2Date;
	# say "subjectId     : $subjectId";
	# p$dosesDates{$subjectId};
	# die if keys %dosesDates > 500;
}
for my $subjectId (sort{$a <=> $b} keys %randomization) {
	next if exists $dosesDates{$subjectId};
	next unless $randomization{$subjectId}->{'randomizationDate'};
	# p$randomization{$subjectId};
	my $dose1Date = $randomization{$subjectId}->{'doses'}->{'1'}->{'doseDate'};
	my $dose2Date = $randomization{$subjectId}->{'doses'}->{'2'}->{'doseDate'};
	my $dose1 = $randomization{$subjectId}->{'doses'}->{'1'}->{'dose'};
	my $dose2 = $randomization{$subjectId}->{'doses'}->{'2'}->{'dose'};
	my $doseDateOrigin = 'Randomization only';
	$dosesDates{$subjectId}->{'doseDateOrigin'} = $doseDateOrigin;
	$dosesDates{$subjectId}->{'dose1'} = $dose1;
	$dosesDates{$subjectId}->{'dose2'} = $dose2;
	$dosesDates{$subjectId}->{'dose1Date'} = $dose1Date;
	$dosesDates{$subjectId}->{'dose2Date'} = $dose2Date;
}

# Generating final stats.
for my $subjectId (sort{$a <=> $b} keys %dosesDates) {
	# say "subjectId : $subjectId";
	# p$randomization{$subjectId};
	# p$dosesDates{$subjectId};
	my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // $dosesDates{$subjectId}->{'dose1'};
	unless ($randomizationGroup) {
		delete $dosesDates{$subjectId};
		next;
	}
	my $randomizationDate  = $randomization{$subjectId}->{'randomizationDate'}  // $dosesDates{$subjectId}->{'dose1Date'} // die;
	my $doseDateOrigin     = $dosesDates{$subjectId}->{'doseDateOrigin'} // die;
	$stats{'randomizationData'}++;
	if ($randomizationDate >= 20200720 && $randomizationDate <= 20201114) {
		$stats{'randomizationFromP1ToCutOff'}->{'total'}++;
		$stats{'randomizationFromP1ToCutOff'}->{$doseDateOrigin}->{'total'}++;
		$stats{'randomizationFromP1ToCutOff'}->{$doseDateOrigin}->{'byGroup'}->{$randomizationGroup}++;
	}
	$dosesDates{$subjectId}->{'randomizationGroup'} = $randomizationGroup;
	$dosesDates{$subjectId}->{'randomizationDate'} = $randomizationDate;
	my $dose1Date = $dosesDates{$subjectId}->{'dose1Date'} // next;
	$stats{'dose1Data'}++;
	if ($dose1Date >= 20200720 && $dose1Date <= 20201114) {
		$stats{'dose1FromP1ToCutOff'}->{'total'}++;
		$stats{'dose1FromP1ToCutOff'}->{$doseDateOrigin}->{'total'}++;
		$stats{'dose1FromP1ToCutOff'}->{$doseDateOrigin}->{'byGroup'}->{$randomizationGroup}++;
	}
	my $dose2Date = $dosesDates{$subjectId}->{'dose2Date'} // next;
	$stats{'dose2Data'}++;
	if ($dose2Date >= 20200720 && $dose2Date <= 20201108) {
		$stats{'dose2FromP1ToCutOff'}->{'total'}++;
		$stats{'dose2FromP1ToCutOff'}->{$doseDateOrigin}->{'total'}++;
		$stats{'dose2FromP1ToCutOff'}->{$doseDateOrigin}->{'byGroup'}->{$randomizationGroup}++;
	}
}
open my $out, '>:utf8', 'public/doc/pfizer_trials/merged_doses_data.json';
print $out encode_json\%dosesDates;
close $out;
p%stats;
say "Printed : " . keys %dosesDates;

sub convert_date {
	my $dt = shift;
	die unless $dt;
	my ($y, $m, $d) = $dt =~ /(....)-(..)-(..) /;
	return "$y$m$d";
}


sub load_adva {
	open my $in, '<:utf8', $advaFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adva = %$json;
	say "[$advaFile] -> patients : " . keys %adva;
}

sub load_randomization_1 {
	open my $in, '<:utf8', $randomizationFile1;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	say "[$randomizationFile1] -> patients : " . keys %randomization;
}

sub load_randomization_2 {
	open my $in, '<:utf8', $randomizationFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	for my $subjectId (sort{$a <=> $b} keys %$json) {
		unless (exists $randomization{$subjectId}->{'doses'}) {
			my %tmp = %{%$json{$subjectId}};
			$randomization{$subjectId} = \%tmp;
		}
		# my %tmp = %{%$json{$subjectId}};
		# $randomization{$subjectId} = \%tmp;
	}
	say "[$randomizationFile2] -> patients : " . keys %randomization;
}

sub verify_doses {
	for my $subjectId (sort{$a <=> $b} keys %randomization) {
		# p$randomization{$subjectId};
		# say "subjectId : $subjectId";
		# die;
		verify_dosage($subjectId);
	}
}

sub verify_dosage {
	my ($subjectId) = @_;
	my $totalPlacebosToSlide = 0;
	my $hasVaccine  = 0;
	my $dNum = 0;
	my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // return;
	for my $doseNum (sort{$a <=> $b} keys %{$randomization{$subjectId}->{'doses'}}) {
		$dNum++;
		my $doseDate = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
		my $dose     = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'dose'};
		if ($dNum <= 2) {
			$dose    = $randomizationGroup;
			$randomization{$subjectId}->{'doses'}->{$doseNum}->{'dose'} = $dose;
		}
		my $dosage   = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'dosage'};
		if ($dosage && $dose eq 'Placebo') {
			$totalPlacebosToSlide++;
		} else {
			$hasVaccine = 1 if $dose ne 'Placebo';
		}
	}
	if ($totalPlacebosToSlide) {
		for my $doseNum (sort{$a <=> $b} keys %{$randomization{$subjectId}->{'doses'}}) {
			my $dose     = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'dose'}     // die;
			my $doseDate = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'doseDate'} // die;
			my $dosage   = $randomization{$subjectId}->{'doses'}->{$doseNum}->{'dosage'};
			my $doseTo   = $doseNum + $totalPlacebosToSlide;
			if ($dosage && $dose eq 'Placebo' && $hasVaccine == 1 && exists $randomization{$subjectId}->{'doses'}->{$doseTo}) {
				$randomization{$subjectId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
				$randomization{$subjectId}->{'doses'}->{$doseTo}->{'dosage'}  = $dosage;
			} else {
				if ($dosage && $dose eq 'Placebo') {
					$randomization{$subjectId}->{'doses'}->{$doseNum}->{'dosage'} = undef;
				}
			}
		}
		# p$randomization{$subjectId};
		# die;
	}
}