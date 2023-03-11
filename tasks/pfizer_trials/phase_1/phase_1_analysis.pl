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
use Date::WeekNumber qw/ iso_week_number /;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use time;

my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $sentinelFile      = 'public/doc/pfizer_trials/FDA-CBER-2021-5683-0023500 to -0023507_125742_S1_M5_c4591001-A-c4591001-phase-1-subjects-from-dmw.csv';
my $randomizationFile = 'public/doc/pfizer_trials/subjects_randomization_dates_merged.json';
my $randomDataFile    = 'public/doc/pfizer_trials/merged_doses_data.json';
my $advaFile          = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $feverFile         = "public/doc/pfizer_trials/S1_M5_c4591001-S-D-ce.json";
my $mbFile            = "public/doc/pfizer_trials/pfizer_mb_patients.json";
my $deviationsFile    = "public/doc/pfizer_trials/pfizer_addv_patients.json";
my $seriousAEFile     = 'public/doc/pfizer_phase_1/20210401_serious_adverse_effects_16_2_7_5.json';
my $allAEFile         = 'public/doc/pfizer_phase_1/20210401_all_adverse_effects_16_2_7_4_1.json';
my %fevers            = ();
my %mbData            = ();
my %advaData          = ();
my %demographic       = ();
my %sentinels         = ();
my %randomization     = ();
my %randomData        = ();
my %deviations        = ();
my %seriousAE         = ();
my %allAEs            = ();

load_ae();
load_mb();
load_adva();
load_exclusion();
load_randomization();
load_random_data();
load_demographic_subjects();
load_sentinel();
load_serious_ae();
load_all_aes();

my %allSubs          = ();
my %presents         = ();
my $phase1Total      = 0;
my %stats            = ();

# Test if every subject in the .PDF file appears in the .XLSX file.
for my $subjectId (sort{$a <=> $b} keys %demographic) {
	my $isPhase1 = $demographic{$subjectId}->{'isPhase1'} // die;
	if ($isPhase1) {
		# die "indeed";
		$stats{'isPhase1'}++;
		die unless exists $sentinels{$subjectId};
	}
}
# 
my %randomizationDates  = ();
my %screeningDates      = ();
my %daysScreenToRando   = ();
my %phase1SubjectsBySrc = ();
my %phase1Subjects      = ();
my %aeNotListed = ();
# open my $out, '>:utf8', 'C4591001_phase_1.csv';
# say $out "uSubjectId;subjectId;ageYears;race;sex;screeningDate;randomizationDate;dose1Datetime;dose2Datetime;";
for my $subjectId (sort{$a <=> $b} keys %sentinels) {
	my $screeningDate  = $sentinels{$subjectId} // die;
	unless (exists $demographic{$subjectId}) {
		# say "subjectId : $subjectId";
		$screeningDates{$screeningDate}->{'missing'}++;
		$stats{'xlsxMissingInPdf'}++;
		die if exists $advaData{$subjectId};
		unless (exists $randomization{$subjectId}) {
			$stats{'xlsxMissingInPdfAndNoRandomization'}++;
		}
		$screeningDate = convert_date($screeningDate);
		($screeningDate) = split ' ', $screeningDate;
		$phase1Subjects{$subjectId}->{'screeningDate'} = $screeningDate;
		my $compScreening = $screeningDate;
		$compScreening =~ s/\D//g;
		$phase1SubjectsBySrc{$compScreening}->{$subjectId} = \%{$phase1Subjects{$subjectId}};
		# say $out ";$subjectId;;;;$screeningDate;;;;";
	} else {
		$screeningDates{$screeningDate}->{'present'}++;
		$screeningDates{$screeningDate}->{'presentSubjects'}->{$subjectId} = 1;
		die unless exists $randomData{$subjectId};
		die unless exists $advaData{$subjectId};
		my $randomizationDate = $randomization{$subjectId}->{'randomizationDate'} // die;
		my $randomizationDateOrigin = $randomization{$subjectId}->{'randomizationDateOrigin'} // die;
		my $doseDateOrigin = $randomData{$subjectId}->{'doseDateOrigin'} // die;
		my $randomizationGroup = $randomData{$subjectId}->{'randomizationGroup'} // die;
		my $actArm = $advaData{$subjectId}->{'actArm'} // die;
		my $ageYears = $demographic{$subjectId}->{'ageYears'} // die;
		my $uSubjectId = $demographic{$subjectId}->{'uSubjectId'} // die;
		my $cohort = $advaData{$subjectId}->{'cohort'} // die;
		my $ageGroup = age_to_age_group($ageYears);
		my $race = $advaData{$subjectId}->{'race'} // die;
		my $trialSiteId = $advaData{$subjectId}->{'trialSiteId'} // die;
		my $sex = $demographic{$subjectId}->{'sex'} // die;
		my $dose1Datetime = $advaData{$subjectId}->{'dose1Datetime'} // die;
		my $dose2Datetime = $advaData{$subjectId}->{'dose2Datetime'} // die;
		$phase1Subjects{$subjectId} = \%{$advaData{$subjectId}};
		for my $label (sort keys %{$demographic{$subjectId}}) {
			next if $label eq 'uSubjectIds';
			my $value = $demographic{$subjectId}->{$label} // die;
			$phase1Subjects{$subjectId}->{$label} = $value;
		}
		for my $label (sort keys %{$randomData{$subjectId}}) {
			my $value = $randomData{$subjectId}->{$label} // die;
			$phase1Subjects{$subjectId}->{$label} = $value;
		}
		my $cohortGroup;
		if ($cohort =~ /BNT162b1/) {
			$cohortGroup = 'BNT162b1';
		} elsif ($cohort =~/BNT162b2/) {
			$cohortGroup = 'BNT162b2';
		} else {
			die "cohort : $cohort";
		}
		# p$advaData{$subjectId};
		# p$mbData{$subjectId};
		# p$phase1Subjects{$subjectId};
		# die;
		# p$randomData{$subjectId};
		# p$advaData{$subjectId};
		# p$demographic{$subjectId};
		# p$randomData{$subjectId};
		# p$deviations{$subjectId};
		# say "dose1Datetime : $dose1Datetime";
		# say "dose2Datetime : $dose2Datetime";
		# die;
		$stats{'byOrigin'}->{$doseDateOrigin}++;
		$stats{'byTrialSites'}->{$trialSiteId}->{'total'}++;
		$stats{'byTrialSites'}->{$trialSiteId}->{$actArm}++;
		$stats{'byCohorts'}->{$cohort}->{'total'}++;
		$stats{'byCohorts'}->{$cohort}->{$ageGroup}->{'total'}++;
		$stats{'byCohorts'}->{$cohort}->{$ageGroup}->{$actArm}->{'total'}++;
		$stats{'byCohortsGroups'}->{$cohortGroup}->{'total'}++;
		$screeningDate                    = convert_date($screeningDate);
		$randomizationDate                = convert_date($randomizationDate);
		my $daysBetweenScreeningAndRandom = time::calculate_days_difference($screeningDate, $randomizationDate);
		my $daysBetweenScreeningAndDose1  = time::calculate_days_difference($screeningDate, $dose1Datetime);
		my $daysBetweenDose1Dose2         = time::calculate_days_difference($dose1Datetime, $dose2Datetime);
		$daysScreenToRando{$daysBetweenScreeningAndRandom}++;
		my $hasAdverseEffects = 'No';
		my $totalAdverseEffects    = 0;

		# Table keeping track of the AE already incremented.
		my %aesByDates = ();
		my %aes = ();
		if (exists $seriousAE{$subjectId}) {
			$hasAdverseEffects = 'Yes - Severe';
			for my $symptomSetNumber (sort keys %{$seriousAE{$subjectId}->{'adverseEffectsSets'}}) {
				for my $symptomNumber (sort keys %{$seriousAE{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}}) {
					$totalAdverseEffects++;
					my $onsetDate = $seriousAE{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'onsetDate'} // die;
					$onsetDate = convert_alpha_date($onsetDate);
					# say "onsetDate : $onsetDate";
					# die;
					my $adverseEffects = $seriousAE{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'adverseEffects'} // die;
					$aes{$onsetDate}->{$adverseEffects} = 1;
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects} = \%{$seriousAE{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}};
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'onsetDate'} = $onsetDate;
					my $outcomeDate = $seriousAE{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'outcomeDate'};
					if ($outcomeDate) {
						$outcomeDate = convert_alpha_date($outcomeDate);
						$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'outcomeDate'} = $outcomeDate;
					}
				}
			}
			for my $symptomSetNumber (sort keys %{$allAEs{$subjectId}->{'adverseEffectsSets'}}) {
				for my $symptomNumber (sort keys %{$allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}}) {
					$totalAdverseEffects++;
					my $onsetDate = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'onsetDate'} // die;
					$onsetDate = convert_alpha_date($onsetDate);
					my $adverseEffects = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'adverseEffects'} // die;
					next if exists $aes{$onsetDate}->{$adverseEffects};
					$aes{$onsetDate}->{$adverseEffects} = 1;
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects} = \%{$allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}};
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'onsetDate'} = $onsetDate;
					my $outcomeDate = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'outcomeDate'};
					if ($outcomeDate) {
						$outcomeDate = convert_alpha_date($outcomeDate);
						$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'outcomeDate'} = $outcomeDate;
					}
				}
			}

			$stats{'seriousAE'}->{'total'}++;
			$stats{'seriousAE'}->{'sIds'}->{$subjectId}++;
			$stats{'seriousAE'}->{'byArm'}->{$actArm}++;
			# p$phase1Subjects{$subjectId};
			# die;
		} elsif (exists $allAEs{$subjectId}) {
			$stats{'allAEs'}->{'total'}++;
			$stats{'allAEs'}->{'byArm'}->{$actArm}++;
			$hasAdverseEffects = 'Yes';
			for my $symptomSetNumber (sort keys %{$allAEs{$subjectId}->{'adverseEffectsSets'}}) {
				for my $symptomNumber (sort keys %{$allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}}) {
					$totalAdverseEffects++;
					my $onsetDate = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'onsetDate'} // die;
					$onsetDate = convert_alpha_date($onsetDate);
					my $adverseEffects = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'adverseEffects'} // die;
					$aes{$onsetDate}->{$adverseEffects} = 1;
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects} = \%{$allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}};
					$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'onsetDate'} = $onsetDate;
					my $outcomeDate = $allAEs{$subjectId}->{'adverseEffectsSets'}->{$symptomSetNumber}->{'adverseEffects'}->{$symptomNumber}->{'outcomeDate'};
					if ($outcomeDate) {
						$outcomeDate = convert_alpha_date($outcomeDate);
						$phase1Subjects{$subjectId}->{'adverseEffects'}->{$totalAdverseEffects}->{'outcomeDate'} = $outcomeDate;
					}
				}
			}
			# p$allAEs{$subjectId};
			# die;
		} else {
			$phase1Subjects{$subjectId}->{'adverseEffects'} = {};
		}
		# If we have additional AEs in the fevers file, processing them.
		if (exists $fevers{$subjectId}) {
			# say "supplementary :";
			# p$fevers{$subjectId};
			# say "serious :";
			# p$seriousAE{$subjectId};
			# say "all :";
			# p$allAEs{$subjectId};
			# die;
			my $hasFever     = 0;
			my $feverFirstDate;
			my $feverFirstSeverity;
			my $feverFirstPostDose;
			my $feverFirstPostDays;
			my $reactionsNum = 0;
			for my $onsetDate (sort{$a <=> $b} keys %{$fevers{$subjectId}->{'aeListed'}}) {
				my ($y, $m, $d) = $onsetDate =~ /(....)(..)(..)/;
				for my $adverseEffects (sort keys %{$fevers{$subjectId}->{'aeListed'}->{$onsetDate}}) {
					my $severity = $fevers{$subjectId}->{'aeListed'}->{$onsetDate}->{$adverseEffects}->{'severity'} || next;
					my $afterShot = $fevers{$subjectId}->{'aeListed'}->{$onsetDate}->{$adverseEffects}->{'afterShot'} || die;
					my $dayAfterDose = $fevers{$subjectId}->{'aeListed'}->{$onsetDate}->{$adverseEffects}->{'dayAfterDose'} || die;
					if ($adverseEffects eq 'FEVER') {
						$hasFever = 1;
						unless ($feverFirstDate) {
							$feverFirstSeverity = $severity;
							$feverFirstDate     = "$y-$m-$d";
							$feverFirstPostDose = $afterShot;
							$feverFirstPostDays = $dayAfterDose;
						}
					}
					$reactionsNum++;
					$phase1Subjects{$subjectId}->{'reactions'}->{$reactionsNum}->{'severity'}  = $severity;
					$phase1Subjects{$subjectId}->{'reactions'}->{$reactionsNum}->{'onsetDate'} = $onsetDate;
					$phase1Subjects{$subjectId}->{'reactions'}->{$reactionsNum}->{'adverseEffects'} = $adverseEffects;
					# say "onsetDate      : $onsetDate";
					# say "adverseEffects : $adverseEffects";
					# die;
				}
			}
			if ($hasFever) {
				$stats{'fevers'}->{'total'}++;
				$stats{'fevers'}->{'sIds'}->{$actArm}->{$subjectId}->{'feverFirstDate'} = $feverFirstDate;
				$stats{'fevers'}->{'sIds'}->{$actArm}->{$subjectId}->{'feverFirstSeverity'} = $feverFirstSeverity;
				$stats{'fevers'}->{'sIds'}->{$actArm}->{$subjectId}->{'feverFirstPostDose'} = $feverFirstPostDose;
				$stats{'fevers'}->{'sIds'}->{$actArm}->{$subjectId}->{'feverFirstPostDays'} = $feverFirstPostDays;
				$stats{'fevers'}->{'byArm'}->{$actArm}++;
			}
			# die "indeed";
		}


		$phase1Subjects{$subjectId}->{'totalAdverseEffects'} = $totalAdverseEffects;
		$phase1Subjects{$subjectId}->{'hasAdverseEffects'} = $hasAdverseEffects;

		# Incrementing known deviations.
		if (exists $deviations{$subjectId}) {
			$phase1Subjects{$subjectId}->{'deviations'} = \%{$deviations{$subjectId}->{'deviations'}};
		} else {
			$phase1Subjects{$subjectId}->{'deviations'} = {};
		}
		my $totalDeviations = keys %{$phase1Subjects{$subjectId}->{'deviations'}};
		$phase1Subjects{$subjectId}->{'totalDeviations'} = $totalDeviations;
		$phase1Subjects{$subjectId}->{'daysBetweenScreeningAndRandom'} = $daysBetweenScreeningAndRandom;
		$phase1Subjects{$subjectId}->{'daysBetweenDose1Dose2'} = $daysBetweenDose1Dose2;
		$phase1Subjects{$subjectId}->{'daysBetweenScreeningAndDose1'} = $daysBetweenScreeningAndDose1;
		if ($daysBetweenScreeningAndDose1 > 14) {
			$stats{'outOf14DaysScreeningToDose1'}->{'total'}++;
			$stats{'outOf14DaysScreeningToDose1'}->{'days'}->{$subjectId} = $daysBetweenScreeningAndDose1;

		}

		# Reformatting visits.
		my %visits = %{$phase1Subjects{$subjectId}->{'visits'}};
		delete $phase1Subjects{$subjectId}->{'visits'};
		my $positiveNBinding = 0;
		my $firstCovidDate;
		for my $visitDate (sort keys %visits) {
			my $visit = $visits{$visitDate}->{'visit'} // die;
			my $visitName;
			if ($visit =~ /V1_/) {
				$visitName = '1';
			} elsif ($visit =~ /V2_/) {
				$visitName = '2';
			} elsif ($visit =~ /V3_/) {
				$visitName = '3';
			} elsif ($visit =~ /V4_/) {
				$visitName = '4';
			} elsif ($visit =~ /V5_/) {
				$visitName = '5';
			} elsif ($visit =~ /V6_/) {
				$visitName = '6';
			} elsif ($visit =~ /V7_/) {
				$visitName = '7';
			} elsif ($visit =~ /V8_/) {
				$visitName = '8';
			} else {
				die "visit : [$visit]";
			}
			if (exists $visits{$visitDate}->{'N-binding antibody - N-binding Antibody Assay'}) {
				if ($visits{$visitDate}->{'N-binding antibody - N-binding Antibody Assay'} eq 'POS') {
					$positiveNBinding++;
					$firstCovidDate = $visitDate unless $firstCovidDate;
				}
			}
			$phase1Subjects{$subjectId}->{'advaVisits'}->{$visitName} = \%{$visits{$visitDate}};
			$phase1Subjects{$subjectId}->{'advaVisits'}->{$visitName}->{'visitDate'} = $visitDate;
		}
		my $positivePCR = 0;
		my $positiveImmunoChromatography = 0;
		# p$mbData{$subjectId};
		for my $visitDate (sort keys %{$mbData{$subjectId}->{'mbVisits'}}) {
			my $visit = $mbData{$subjectId}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
			my $visitName;
			if ($visit =~ /SCR/) {
				$visitName = '0';
			} elsif ($visit =~ /V1_/) {
				$visitName = '1';
			} elsif ($visit =~ /V2_/) {
				$visitName = '2';
			} elsif ($visit =~ /V3_/) {
				$visitName = '3';
			} elsif ($visit =~ /V4_/) {
				$visitName = '4';
			} elsif ($visit =~ /V5_/) {
				$visitName = '5';
			} elsif ($visit =~ /V6_/) {
				$visitName = '6';
			} elsif ($visit =~ /V7_/) {
				$visitName = '7';
			} elsif ($visit =~ /V8_/) {
				$visitName = '8';
			} elsif ($visit =~ /COVID_A/ || $visit =~ /COVID_B/) { # To investigate further, first subject concerned, 10011005, has no documented Covid.
				next;
			} else {
				die "visit : [$visit]";
			}
			if (exists $mbData{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}) {
				if ($mbData{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'} eq 'POS') {
					$positivePCR++;
					$firstCovidDate = $visitDate unless $firstCovidDate;
				}
			}
			if (exists $mbData{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}) {
				if ($mbData{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'} eq 'POSITIVE') {
					$positiveImmunoChromatography++;
					$firstCovidDate = $visitDate unless $firstCovidDate;
				}
			}
			$phase1Subjects{$subjectId}->{'mbVisits'}->{$visitName} = \%{$mbData{$subjectId}->{'mbVisits'}->{$visitDate}};
			$phase1Subjects{$subjectId}->{'mbVisits'}->{$visitName}->{'visitDate'} = $visitDate;
		}
		$phase1Subjects{$subjectId}->{'positiveNBinding'} = $positiveNBinding;
		$phase1Subjects{$subjectId}->{'positivePCR'} = $positivePCR;
		$phase1Subjects{$subjectId}->{'positiveImmunoChromatography'} = $positiveImmunoChromatography;
		$phase1Subjects{$subjectId}->{'firstCovidDate'} = $firstCovidDate;
		if ($positiveNBinding) {
			$stats{'positiveNBindings'}->{$randomizationGroup}++;
		}
		if ($positivePCR) {
			$stats{'positivePCRs'}->{$randomizationGroup}++;
		}
		if ($positiveImmunoChromatography) {
			$stats{'positiveImmunoChromatographys'}->{$randomizationGroup}++;
		}
		($screeningDate) = split ' ', $screeningDate;
		$phase1Subjects{$subjectId}->{'screeningDate'} = $screeningDate;
		($randomizationDate) = split ' ', $randomizationDate;
		$phase1Subjects{$subjectId}->{'randomizationDate'} = $randomizationDate;
		$phase1Subjects{$subjectId}->{'randomizationDateOrigin'} = $randomizationDateOrigin;
		die unless $randomizationDateOrigin eq 'Randomization file';
		my ($dose1Date) = split ' ', $phase1Subjects{$subjectId}->{'dose1Datetime'};
		$phase1Subjects{$subjectId}->{'dose1Date'} = $dose1Date;
		my ($dose2Date) = split ' ', $phase1Subjects{$subjectId}->{'dose2Datetime'};
		$phase1Subjects{$subjectId}->{'dose2Date'} = $dose2Date;
		my $compScreening = $screeningDate;
		$compScreening =~ s/\D//g;
		$phase1SubjectsBySrc{$compScreening}->{$subjectId} = \%{$phase1Subjects{$subjectId}};
		# p$phase1Subjects{$subjectId};
		# p%visits;
		# die;
		# say $out "$uSubjectId;$subjectId;$ageYears;$race;$sex;$screeningDate;$randomizationDate;$dose1Datetime;$dose2Datetime;";
		# p$randomData{$subjectId};
		# p$advaData{$subjectId};
		# say "$subjectId | $screeningDate - $randomizationDate -> $daysBetweenScreeningAndRandom";
		# die;
		# p$randomization{$subjectId};




		# $stats{'daysBetweenDoses'}->{$actArm}->{$daysBetweenDose1Dose2}->{'total'}++;
		# $stats{'daysBetweenDoses'}->{$actArm}->{$daysBetweenDose1Dose2}->{'subjects'}->{$subjectId}++;
	}
}
# close $out;

open my $out, '>:utf8', 'public/doc/pfizer_trials/phase1Subjects.json';
print $out encode_json\%phase1Subjects;
close $out;
open my $out2, '>:utf8', 'public/doc/pfizer_trials/phase1SubjectsByScreeningDate.json';
print $out2 encode_json\%phase1SubjectsBySrc;
close $out2;

p%stats;

# my %datesRandomized = ();
# my $sumRandomized   = 0;
# my $milestone45     = 0;
# p%randomizationDates;
# for my $compDate (sort{$a <=> $b} keys %randomizationDates) {
# 	my $subjects    = $randomizationDates{$compDate}->{'present'} // die;
# 	$sumRandomized += $subjects;
# 	if ($sumRandomized >= 45 && !$milestone45) {
# 		say "[$sumRandomized] achieved on [$compDate]";
# 		$milestone45 = 1;
# 	}
# 	if ($compDate == 20200618) {
# 		say "[$sumRandomized] achieved on [$compDate]";
# 	}
# }
# p%randomizationDates;
# p%daysScreenToRando;
# p%stats;

sub convert_date {
	my $date = shift;
	my ($y, $m, $d) = $date =~ /(....)(..)(..)/;
	return "$y-$m-$d 12:00:00";
}

sub convert_alpha_date {
	my $dt = shift;
	my ($d, $m, $y) = $dt =~ /(..)(...)(....)/;
	$m = convert_month($m);
	my $weekNumber = iso_week_number("$y-$m-$d");
	(undef, $weekNumber) = split '-', $weekNumber;
	$weekNumber =~ s/W//;
	return "$y-$m-$d";
}

sub convert_month {
	my $m = shift;
	return '01' if $m eq 'JAN';
	return '02' if $m eq 'FEB';
	return '03' if $m eq 'MAR';
	return '04' if $m eq 'APR';
	return '05' if $m eq 'MAY';
	return '06' if $m eq 'JUN';
	return '07' if $m eq 'JUL';
	return '08' if $m eq 'AUG';
	return '09' if $m eq 'SEP';
	return '10' if $m eq 'OCT';
	return '11' if $m eq 'NOV';
	return '12' if $m eq 'DEC';
	die "failed to convert month";
}


sub load_demographic_subjects {
	open my $in, '<:utf8', $demographicFile or die "Missing file [$demographicFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographic = %$json;
	say "[$demographicFile] -> subjects : " . keys %demographic;
}

sub load_sentinel {
	open my $in, '<:utf8', $sentinelFile or die "Missing file [$sentinelFile]";
	while (<$in>) {
		chomp $_;
		my ($subjectId, $screeningDate) = split ';', $_;
		next if $subjectId eq 'SUBJECTNUMBERSTR';
		die unless $subjectId =~ /^\d\d\d\d\d\d\d\d$/;
		my ($d, $m, $y) = $screeningDate =~ /(.*)\/(.*)\/(.*)/;
		$screeningDate = "$y$m$d";
		$sentinels{$subjectId} = $screeningDate;
	}
	close $in;
	say "[$sentinelFile] -> subjects : " . keys %sentinels;
}

sub load_serious_ae {
	open my $in, '<:utf8', $seriousAEFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%seriousAE = %$json;
	say "[$seriousAEFile] -> subjects : " . keys %seriousAE;
}

sub load_all_aes {
	open my $in, '<:utf8', $allAEFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%allAEs = %$json;
	say "[$allAEFile] -> subjects : " . keys %allAEs;
}

sub load_exclusion {
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

sub load_randomization {
	open my $in, '<:utf8', $randomizationFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	# p%randomization;die;
	say "[$randomizationFile] -> subjects : " . keys %randomization;
}

sub load_random_data {
	open my $in, '<:utf8', $randomDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomData = %$json;
	say "[$randomDataFile] -> subjects : " . keys %randomData;
}

sub load_adva {
	open my $in, '<:utf8', $advaFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
	say "[$advaFile] -> subjects : " . keys %advaData;
}

sub load_mb {
	open my $in, '<:utf8', $mbFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%mbData = %$json;
	say "[$mbFile] -> subjects : " . keys %mbData;
}

sub load_ae {
	open my $in, '<:utf8', $feverFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%fevers = %$json;
	say "[$feverFile] -> subjects : " . keys %fevers;
}

sub age_to_age_group {
	my $ageYears = shift;
	my $ageGroup;
	if ($ageYears >= 18 && $ageYears <= 55) {
		$ageGroup = '18 - 55';
	} elsif ($ageYears >= 65 && $ageYears <= 85) {
		$ageGroup = '65 - 85';
	} else {
		die "ageYears : $ageYears";
	}
	return $ageGroup;
}