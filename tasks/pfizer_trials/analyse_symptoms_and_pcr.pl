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
use time;

# Treatment configuration.
my $daysOffset           = 4;
my $symptomsBeforePCR    = 1; # 0 = before non included ; 1 = before included.
my $officialSymptomsOnly = 1; # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.

# Loading data required.
my $exclusionsFile    = 'public/doc/pfizer_trials/pfizer_excluded_patients.json';
my $deviationsFile    = 'public/doc/pfizer_trials/pfizer_sddv_patients.json';
my $pcrTestsFile      = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $symptomsFile      = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $randomizationFile = 'public/doc/pfizer_trials/merged_doses_data.json';
my $p1SubjectsFile    = 'public/doc/pfizer_trials/phase1Subjects.json';
my $demographicFile   = 'public/doc/pfizer_trials/pfizer_trial_demographics_merged.json';
my $pdfCasesFile      = 'public/doc/pfizer_trials/pfizer_trial_cases_merged.json';
my %demographics      = ();
my %phase1Subjects    = ();
my %exclusions        = ();
my %deviations        = ();
my %pcrTests          = ();
my %symptoms          = ();
my %randomization     = ();
my %pdfCases          = ();
load_demographics();
load_phase_1();
load_randomization();
load_exclusions();
load_deviations();
load_pcr_tests();
load_symptoms();
load_pdf_cases();

my %stats = ();
my %weeklyStats = ();

# Flushing .PDF cases & exclusions post cut-off on November 14.
delete_post_cutoff_pdf_cases();
# Isolating subjects with positive PCRs & evaluating PCR related stats.
my %subjectsWithPCRs         = ();
my %subjectsVisitsConfirmed  = ();
pcr_positive_data();
# Verifying if we found all the positive cases listed in the .PDF.
eval_pdf_positive_cases_to_analysis();
my %symptomsByGroups     = ();
my %subjectsWithSymptoms = ();
symptoms_positive_data();

sub load_demographics {
	open my $in, '<:utf8', $demographicFile or die "Missing file [$demographicFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%demographics = %$json;
	say "[$demographicFile] -> patients : " . keys %demographics;
}

sub load_phase_1 {
	open my $in, '<:utf8', $p1SubjectsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%phase1Subjects = %$json;
	# p%phase1Subjects;die;
	say "[$p1SubjectsFile] -> subjects : " . keys %phase1Subjects;
}

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
	# p$pcrTests{'44441222'};
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
	# p$symptoms{'44441222'};
	# die;
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
	say "[$randomizationFile] -> subjects : " . keys %randomization;
}

sub load_pdf_cases {
	open my $in, '<:utf8', $pdfCasesFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfCases = %$json;
	say "[$pdfCasesFile] -> subjects : " . keys %pdfCases;
}

sub delete_post_cutoff_pdf_cases {
	for my $subjectId (sort{$a <=> $b} keys %pdfCases) {
		unless ($pdfCases{$subjectId}->{'swabDate'} <= 20201114) {
			delete $pdfCases{$subjectId};
		}
	}
}

sub pcr_positive_data {
	open my $out, '>:utf8', 'full_pcr_list.csv';
	open my $out2, '>:utf8', 'positive_pcr_list.csv';
	open my $out3, '>:utf8', 'positive_pcr_with_symptoms_list.csv';
	say $out "SubjectId;Randomization Group;Visit Date;PCR Result;";
	say $out2 "SubjectId;Randomization Group;First Positive PCR Date;";
	say $out3 "SubjectId;Randomization Group;First Positive PCR Date;Symptom Datetime;Suspected Covid N°;" .
		 "New Or Increased Cough;New Or Increased Sore Throat;Chills;Fever;Diarrhea;New Loss Of Taste Or Smell;" .
		 "New Or Increased Shortness Of Breath;Fever;New Or Increased Muscle Pain;Vomiting;New Or Increased Nasal Congestion;" .
		 "Headache;Fatigue;Rhinorrhoea;Nausea;New Or Increased Wheezing;";
	my %subjectsSymptoms = ();
	for my $subjectId (sort{$a <=> $b} keys %pcrTests) {
		my $firstPositivePCRDate;

		# Reorganizing visits by dates.
		my ($hasPositivePCR,
			%pcrsByDates)      = subject_pcrs_by_dates($subjectId);
		my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
		unless (keys %pcrsByDates) {
			$stats{'pcrAnalysis'}->{'subjects'}->{'withoutPCRData'}++;
			next;
		}
		$stats{'pcrAnalysis'}->{'subjects'}->{'withPCRs'}++;

		# Fetching total PCRs performed.
		for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
			my $pcrResult = $pcrsByDates{$visitCompdate}->{'pcrResult'} // die;
			my $visitDate = $pcrsByDates{$visitCompdate}->{'visitDate'} // die;
			say $out "$subjectId;$randomizationGroup;$visitDate;$pcrResult;";
			$stats{'pcrAnalysis'}->{'PCRs'}->{'totalDone'}++;
			if ($pcrsByDates{$visitCompdate}->{'pcrResult'} eq 'POS') {
				$stats{'pcrAnalysis'}->{'PCRs'}->{'totalPositive'}++;
			}
		}
		next unless $hasPositivePCR;
		$subjectsWithPCRs{$subjectId}->{'randomizationGroup'} = $randomizationGroup;
		$stats{'pcrAnalysis'}->{'subjects'}->{'withPositivePCRs'}->{$randomizationGroup}++;
		$stats{'pcrAnalysis'}->{'subjects'}->{'withPositivePCRs'}->{'total'}++;
		# say "*" x 50;
		# say "subjectId            : $subjectId";

		# Fetching first Covid confirmation.
		for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
			if ($pcrsByDates{$visitCompdate}->{'pcrResult'} eq 'POS') {
				$firstPositivePCRDate = $visitCompdate;
				last;
			}
		}
		die unless $firstPositivePCRDate;
		my ($fY, $fM, $fD)       = $firstPositivePCRDate =~ /(....)(..)(..)/;
		$firstPositivePCRDate    = "$fY-$fM-$fD";
		my $hasCovidWithSymptoms = 0;
		$subjectsWithPCRs{$subjectId}->{'firstPositivePCRDate'} = $firstPositivePCRDate;
		say $out2 "$subjectId;$randomizationGroup;$firstPositivePCRDate;";
		if (exists $phase1Subjects{$subjectId}) {
			$subjectsWithPCRs{$subjectId}->{'isPhase1'} = 'Yes';
		} else {
			$subjectsWithPCRs{$subjectId}->{'isPhase1'} = 'No';
		}
		my $closestDayFromSymptomToCovid = 99;
		my $ongoingCovidDate;
		my ($hasSymptoms, %symptomsByDates) = subject_symptoms_by_dates($subjectId);

		# if ($subjectId == '11331263') {
		# 	p%pcrsByDates;
		# 	die;
		# }

		# If we have no symptom data, or no symptom data up to cutt-off date, simply incrementing the positive PCRs observed on the subject.
		unless (exists $symptoms{$subjectId} && $hasSymptoms) {
			$subjectsWithPCRs{$subjectId}->{'hasSymptomData'} = 'No';
			$stats{'pcrAnalysis'}->{'subjects'}->{'noSymptomData'}->{'total'}++;
			$stats{'pcrAnalysis'}->{'subjects'}->{'noSymptomData'}->{$randomizationGroup}++;
			$closestDayFromSymptomToCovid = undef;
			for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
				if ($pcrsByDates{$visitCompdate}->{'pcrResult'} eq 'POS') {
					my $visitDate     = $pcrsByDates{$visitCompdate}->{'visitDate'} // die;
					$ongoingCovidDate = $visitCompdate unless $ongoingCovidDate;
					$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'pcrResult'} = $pcrsByDates{$visitCompdate}->{'pcrResult'};
					$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'visitDate'} = $visitDate;
				} else {
					if ($ongoingCovidDate) {
						$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$ongoingCovidDate}->{'confirmedNegativeDate'} = $visitCompdate;
						$ongoingCovidDate = undef;
					}
				}
			}
		} else {

			# If we have symptoms reported, verifying offset between symptoms & positive diagnose.
			$subjectsWithPCRs{$subjectId}->{'hasSymptomData'} = 'Yes';
			for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
				if ($pcrsByDates{$visitCompdate}->{'pcrResult'} eq 'POS') {
					# say "visitCompdate : $visitCompdate";
					my $visitDate     = $pcrsByDates{$visitCompdate}->{'visitDate'} // die;
					$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'pcrResult'} = $pcrsByDates{$visitCompdate}->{'pcrResult'};
					$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'visitDate'} = $visitDate;
					$ongoingCovidDate = $visitCompdate unless $ongoingCovidDate;
					my $visitDatetime = "$visitDate 12:00:00";
					for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
						if (!$symptomsBeforePCR) { # If symptomsBeforePCR = 0, skipping the symptoms which have occured before the PCR.
							next if $symptomCompdate < $visitCompdate; # Verify that the symptom have occured on the day or after the PCR.
						}
						# say "symptomCompdate : $symptomCompdate";
						my $visitName   = $symptomsByDates{$symptomCompdate}->{'visitName'} // die;
						# say "visitName : $visitName";
						my $symptomDatetime   = $symptomsByDates{$symptomCompdate}->{'symptomDatetime'} // die;
						my $daysDifference    = time::calculate_days_difference($symptomDatetime, $visitDatetime);
						last if $visitCompdate < $symptomCompdate && $daysDifference > $daysOffset; # If the symptoms have occurred within the X days window, counting the case as symptomatic with Covid.
						next if $daysDifference > $daysOffset;
						$subjectsVisitsConfirmed{$subjectId}->{$visitName} = 1;
						$hasCovidWithSymptoms = 1;
						my $difToZero = abs(0 - $daysDifference);
						$closestDayFromSymptomToCovid = $difToZero if $difToZero < $closestDayFromSymptomToCovid;
						unless (exists $subjectsSymptoms{$subjectId}) {
							my $weekNumber = time::week_number_from_date($visitDate);
							$weeklyStats{'PCRWithSymptoms'}->{$weekNumber}->{$randomizationGroup}++;
							$subjectsSymptoms{$subjectId} = 1;
							my $symptomDatetime = $symptomsByDates{$symptomCompdate}->{'symptomDatetime'} // 0;
							my $visitName = $symptomsByDates{$symptomCompdate}->{'visitName'} // 0;
							my $newOrIncreasedCough = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED COUGH'} // 0;
							my $newOrIncreasedSoreThroat = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SORE THROAT'} // 0;
							my $chills = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'CHILLS'} // 0;
							my $fever  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FEVER'} // 0;
							my $diarrhea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'DIARRHEA'} // 0;
							my $newLossOfTasteOrSmell  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW LOSS OF TASTE OR SMELL'} // 0;
							my $newOrIncreasedShortnessOfBreath = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SHORTNESS OF BREATH'} // 0;
							my $newOrIncreasedMusclePain = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED MUSCLE PAIN'} // 0;
							my $vomiting  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'VOMITING'} // 0;
							my $newOrIncreasedNasalCongestion  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED NASAL CONGESTION'} // 0;
							my $headache  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'HEADACHE'} // 0;
							my $fatigue  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FATIGUE'} // 0;
							my $rhinorrhoea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'RHINORRHOEA'} // 0;
							my $nausea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NAUSEA'} // 0;
							my $newOrIncreasedWheezing  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED WHEEZING'} // 0;
							say $out3 "$subjectId;$randomizationGroup;$firstPositivePCRDate;$symptomDatetime;$visitName;" .
									 "$newOrIncreasedCough;$newOrIncreasedSoreThroat;$chills;$fever;$diarrhea;$newLossOfTasteOrSmell;" .
									 "$newOrIncreasedShortnessOfBreath;$fever;$newOrIncreasedMusclePain;$vomiting;$newOrIncreasedNasalCongestion;" .
									 "$headache;$fatigue;$rhinorrhoea;$nausea;$newOrIncreasedWheezing;";
						}
						$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'symptomsPostPCR'}->{$daysDifference}->{'visitName'} = $symptomsByDates{$symptomCompdate}->{'visitName'};
						for my $symptomName (sort keys %{$symptomsByDates{$symptomCompdate}->{'symptoms'}}) {
							$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'symptomsPostPCR'}->{$daysDifference}->{'symptomDatetime'} = $symptomDatetime;
							push @{$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$visitCompdate}->{'symptomsPostPCR'}->{$daysDifference}->{'symptoms'}}, $symptomName;
						}
						# say "$symptomDatetime -> $visitDate ($daysDifference days)";
					}
				} else {
					if ($ongoingCovidDate) {
						$subjectsWithPCRs{$subjectId}->{'positivePCRs'}->{$ongoingCovidDate}->{'confirmedNegativeDate'} = $visitCompdate;
						$ongoingCovidDate = undef;
					}
				}
			}
			# say "------>";
			# say "hasCovidWithSymptoms         : $hasCovidWithSymptoms";
			# say "closestDayFromSymptomToCovid : $closestDayFromSymptomToCovid";
			# p$subjectsWithPCRs{$subjectId};
			# die;
			if ($hasCovidWithSymptoms) {
				$stats{'pcrAnalysis'}->{'subjects'}->{'positiveWithSymptoms'}->{$randomizationGroup}++;
				$stats{'pcrAnalysis'}->{'subjects'}->{'positiveWithSymptoms'}->{'total'}++;
				unless (exists $pdfCases{$subjectId}) {
					# say "Subject [$subjectId] ($randomizationGroup) isn't listed as a case in PDF.";
					$stats{'pcrAnalysis'}->{'subjects'}->{'nonListedInPDF'}->{$randomizationGroup}->{'total'}++;
					$stats{'pcrAnalysis'}->{'subjects'}->{'nonListedInPDF'}->{$randomizationGroup}->{'subjects'}->{$subjectId}++;
				}
				# p$randomization{$subjectId};
				# die;
			} else {
				$closestDayFromSymptomToCovid = undef;
				$stats{'pcrAnalysis'}->{'subjects'}->{'positiveWithoutSymptoms'}->{$randomizationGroup}++;
				$stats{'pcrAnalysis'}->{'subjects'}->{'positiveWithoutSymptoms'}->{'total'}++;
			}
			$subjectsWithPCRs{$subjectId}->{'hasCovidWithSymptoms'} = $hasCovidWithSymptoms;
			$subjectsWithPCRs{$subjectId}->{'closestDayFromSymptomToCovid'} = $closestDayFromSymptomToCovid;
		}
		$stats{'totalPositivePCRs'}->{$randomizationGroup}++;
		$stats{'totalPositivePCRs'}->{'total'}++;
	}
	close $out;
	close $out2;
	close $out3;
}

sub subject_pcrs_by_dates {
	my $subjectId      = shift;
	my %pcrsByDates    = ();
	my $hasPositivePCR = 0;
	for my $visitDate (sort keys %{$pcrTests{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= 20201114;
		my $pcrResult = $pcrTests{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		$pcrsByDates{$visitCompdate}->{'visitDate'} = $visitDate;
		$pcrsByDates{$visitCompdate}->{'pcrResult'} = $pcrResult;
		if ($pcrResult eq 'POS') {
			$hasPositivePCR = 1;
		}
	}
	return ($hasPositivePCR,
		%pcrsByDates);
}

sub subject_symptoms_by_dates {
	my $subjectId       = shift;
	# p$symptoms{$subjectId};
	# die;
	my %symptomsByDates = ();
	my $hasSymptoms     = 0;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		next unless $symptomCompdate <= 20201114;
		my $totalSymptoms   = 0;
		my $hasOfficialSymptoms = 0;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}}) {
			next unless $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}->{$symptomName} eq 'Y';
			my $symptomCategory = symptom_category_from_symptom($symptomName);
			if ($officialSymptomsOnly) {
				next unless $symptomCategory eq 'OFFICIAL';
			}
			$hasOfficialSymptoms = 1 if $symptomCategory eq 'OFFICIAL';
			$symptomsByDates{$symptomCompdate}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms = 1;
		$symptomsByDates{$symptomCompdate}->{'visitName'}           = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'visitName'};
		$symptomsByDates{$symptomCompdate}->{'symptomDatetime'}     = $symptomDatetime;
		$symptomsByDates{$symptomCompdate}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByDates{$symptomCompdate}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	# p%symptomsByDates;
	# die;
	return (
		$hasSymptoms,
		%symptomsByDates);
}

sub symptom_category_from_symptom {
	my $symptomName = shift;
	my $symptomCategory;
	if (
		$symptomName eq 'NEW OR INCREASED COUGH' ||
		$symptomName eq 'NEW OR INCREASED SORE THROAT' ||
		$symptomName eq 'CHILLS' ||
		$symptomName eq 'FEVER' ||
		$symptomName eq 'DIARRHEA' ||
		$symptomName eq 'NEW LOSS OF TASTE OR SMELL' ||
		$symptomName eq 'NEW OR INCREASED SHORTNESS OF BREATH' ||
		$symptomName eq 'NEW OR INCREASED MUSCLE PAIN' ||
		$symptomName eq 'VOMITING'
	) {
		$symptomCategory = 'OFFICIAL';
	} elsif (
		$symptomName eq 'NEW OR INCREASED NASAL CONGESTION' ||
		$symptomName eq 'HEADACHE' ||
		$symptomName eq 'FATIGUE' ||
		$symptomName eq 'RHINORRHOEA' ||
		$symptomName eq 'NAUSEA' ||
		$symptomName eq 'NEW OR INCREASED WHEEZING'
	) {
		$symptomCategory = 'SECONDARY';
	} else {
		die "symptomName : $symptomName";
	}
	return $symptomCategory;
}

sub eval_pdf_positive_cases_to_analysis {
	for my $subjectId (sort{$a <=> $b} keys %pdfCases) {
		next unless $pdfCases{$subjectId}->{'swabDate'} <= 20201114;
		# die;
		my $randomizationGroup = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
		unless ($subjectsWithPCRs{$subjectId}->{'hasCovidWithSymptoms'}) {
			# say "Subject [$subjectId] ($randomizationGroup) is listed as a case in PDF but doesn't come out from analysis.";
			$stats{'pdfCases'}->{'subjects'}->{'notFoundOnAnalysis'}->{$randomizationGroup}->{'total'}++;
			$stats{'pdfCases'}->{'subjects'}->{'notFoundOnAnalysis'}->{$randomizationGroup}->{'subjects'}->{$subjectId}++;
		}
		$stats{'pdfCases'}->{'subjects'}->{'total'}->{$randomizationGroup}++;
	}
}

# Then isolating subjects who had "Covid-like" symptoms.
sub symptoms_positive_data {
	open my $out, '>:utf8', 'symptomatic_cases.csv';
	say $out "Subject Id;Randomization Group;Symptom Datetime;Suspected Covid N°;" .
			 "New Or Increased Cough;New Or Increased Sore Throat;Chills;Fever;Diarrhea;New Loss Of Taste Or Smell;" .
			 "New Or Increased Shortness Of Breath;Fever;New Or Increased Muscle Pain;Vomiting;New Or Increased Nasal Congestion;" .
			 "Headache;Fatigue;Rhinorrhoea;Nausea;New Or Increased Wheezing;";
	open my $out2, '>:utf8', 'symptomatic_cases_unconfirmed.csv';
	say $out2 "Subject Id;Randomization Group;Symptom Datetime;Suspected Covid N°;Has Official Symptoms;" .
			 "New Or Increased Cough;New Or Increased Sore Throat;Chills;Fever;Diarrhea;New Loss Of Taste Or Smell;" .
			 "New Or Increased Shortness Of Breath;Fever;New Or Increased Muscle Pain;Vomiting;New Or Increased Nasal Congestion;" .
			 "Headache;Fatigue;Rhinorrhoea;Nausea;New Or Increased Wheezing;";
	for my $subjectId (sort{$a <=> $b} keys %symptoms) {
		die if exists $phase1Subjects{$subjectId};
		my $randomizationGroup  = $randomization{$subjectId}->{'randomizationGroup'} // 'Unknown';
		my $ageYears            = $demographics{$subjectId}->{'ageYears'}            // 'Unknown';
		if (exists $exclusions{$subjectId}) {
			# p$exclusions{$subjectId};
			# die;
			$stats{'symptomsAnalysis'}->{'subjects'}->{'excludedSubjects'}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'subjects'}->{'excludedSubjects'}->{$randomizationGroup}++;
			# next;
		}
		# p$symptoms{$subjectId};
		# die;
		# Reorganizing symptoms by dates.
		my ($hasSymptoms, %symptomsByDates) = subject_symptoms_by_dates($subjectId);
		next unless keys %symptomsByDates && $hasSymptoms;

		# printing raw .CSV data.
		for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
			my $symptomDatetime = $symptomsByDates{$symptomCompdate}->{'symptomDatetime'} // 0;
			my ($symptomDate) = split ' ', $symptomDatetime;
			my $visitName = $symptomsByDates{$symptomCompdate}->{'visitName'} // 0;
			my $newOrIncreasedCough = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED COUGH'} // 0;
			my $newOrIncreasedSoreThroat = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SORE THROAT'} // 0;
			my $chills = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'CHILLS'} // 0;
			my $fever  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FEVER'} // 0;
			my $diarrhea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'DIARRHEA'} // 0;
			my $newLossOfTasteOrSmell  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW LOSS OF TASTE OR SMELL'} // 0;
			my $newOrIncreasedShortnessOfBreath = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SHORTNESS OF BREATH'} // 0;
			my $newOrIncreasedMusclePain = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED MUSCLE PAIN'} // 0;
			my $vomiting  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'VOMITING'} // 0;
			my $newOrIncreasedNasalCongestion  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED NASAL CONGESTION'} // 0;
			my $headache  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'HEADACHE'} // 0;
			my $fatigue  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FATIGUE'} // 0;
			my $rhinorrhoea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'RHINORRHOEA'} // 0;
			my $nausea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NAUSEA'} // 0;
			my $newOrIncreasedWheezing  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED WHEEZING'} // 0;
			say $out "$subjectId;$randomizationGroup;$symptomDatetime;$visitName;" .
					 "$newOrIncreasedCough;$newOrIncreasedSoreThroat;$chills;$fever;$diarrhea;$newLossOfTasteOrSmell;" .
					 "$newOrIncreasedShortnessOfBreath;$fever;$newOrIncreasedMusclePain;$vomiting;$newOrIncreasedNasalCongestion;" .
					 "$headache;$fatigue;$rhinorrhoea;$nausea;$newOrIncreasedWheezing;";
			my $weekNumber = time::week_number_from_date($symptomDate);
			$weeklyStats{'symptoms'}->{$weekNumber}->{$randomizationGroup}++;
		}
		$stats{'symptomsAnalysis'}->{'subjects'}->{'withSymptoms'}->{'total'}++;
		$stats{'symptomsAnalysis'}->{'subjects'}->{'withSymptoms'}->{$randomizationGroup}++;

		# Reorganizing visits by dates.
		my ($hasPositivePCR,
			%pcrsByDates)      = subject_pcrs_by_dates($subjectId);

		# say "*" x 50;
		# say "subjectId            : $subjectId";
		# say "randomizationGroup   : $randomizationGroup";
		my $lastCovidDate;
		my $hasSymptomsWithTest         = 0;
		my $hasSymptomsWithPositiveTest = 0;
		# p%symptomsByDates;
		# die;
		for my $symptomCompdate (sort{$a <=> $b} keys %symptomsByDates) {
			my $symptomDatetime   = $symptomsByDates{$symptomCompdate}->{'symptomDatetime'} // die;
			my $totalSymptoms = $symptomsByDates{$symptomCompdate}->{'totalSymptoms'} || die;
			my $visitName     = $symptomsByDates{$symptomCompdate}->{'visitName'}     || die;
			my $hasOfficialSymptoms     = $symptomsByDates{$symptomCompdate}->{'hasOfficialSymptoms'}     // die;
			unless (exists $subjectsVisitsConfirmed{$subjectId}->{$visitName}) {
				my $newOrIncreasedCough = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED COUGH'} // 0;
				my $newOrIncreasedSoreThroat = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SORE THROAT'} // 0;
				my $chills = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'CHILLS'} // 0;
				my $fever  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FEVER'} // 0;
				my $diarrhea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'DIARRHEA'} // 0;
				my $newLossOfTasteOrSmell  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW LOSS OF TASTE OR SMELL'} // 0;
				my $newOrIncreasedShortnessOfBreath = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED SHORTNESS OF BREATH'} // 0;
				my $newOrIncreasedMusclePain = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED MUSCLE PAIN'} // 0;
				my $vomiting  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'VOMITING'} // 0;
				my $newOrIncreasedNasalCongestion  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED NASAL CONGESTION'} // 0;
				my $headache  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'HEADACHE'} // 0;
				my $fatigue  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'FATIGUE'} // 0;
				my $rhinorrhoea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'RHINORRHOEA'} // 0;
				my $nausea  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NAUSEA'} // 0;
				my $newOrIncreasedWheezing  = $symptomsByDates{$symptomCompdate}->{'symptoms'}->{'NEW OR INCREASED WHEEZING'} // 0;
				say $out2 "$subjectId;$randomizationGroup;$symptomDatetime;$visitName;$hasOfficialSymptoms;" .
						 "$newOrIncreasedCough;$newOrIncreasedSoreThroat;$chills;$fever;$diarrhea;$newLossOfTasteOrSmell;" .
						 "$newOrIncreasedShortnessOfBreath;$fever;$newOrIncreasedMusclePain;$vomiting;$newOrIncreasedNasalCongestion;" .
						 "$headache;$fatigue;$rhinorrhoea;$nausea;$newOrIncreasedWheezing;";
				$stats{'symptomsPlusPCRs'}->{'casesSuspectedButUnconfirmed'}->{'total'}++;
				$stats{'symptomsPlusPCRs'}->{'casesSuspectedButUnconfirmed'}->{$randomizationGroup}++;
				if ($hasOfficialSymptoms) {
					$stats{'symptomsPlusPCRs'}->{'officialCasesSuspectedButUnconfirmed'}->{'total'}++;
					$stats{'symptomsPlusPCRs'}->{'officialCasesSuspectedButUnconfirmed'}->{$randomizationGroup}++;
				}
			} else {
				$stats{'symptomsPlusPCRs'}->{'casesConfirmed'}++;
			}
			$stats{'symptomsPlusPCRs'}->{'total'}++;
			# say "symptomDatetime             : $symptomDatetime";
			# say "totalSymptoms               : $totalSymptoms";
			# say "visitName                   : $visitName";
			$stats{'symptomsPlusPCRs'}->{'byTotalSymptoms'}->{$randomizationGroup}->{$totalSymptoms}++;

			# Fetching nearest test from the symptoms occurence.
			my $symptomsWithTest = 0;
			my $closestDayFromSymptomToTest = 99;
			# $symptomsByGroups{$randomizationGroup}->{'byAges'}->{$ageYears}++;
			# say "symptomCompdate : $symptomCompdate";
			# die;
			# p%pcrsByDates;
			# die;
			for my $visitCompdate (sort{$a <=> $b} keys %pcrsByDates) {
				my $visitDate      = $pcrsByDates{$visitCompdate}->{'visitDate'} // die;
				my $pcrResult      = $pcrsByDates{$visitCompdate}->{'pcrResult'} // die;
				my $visitDatetime  = "$visitDate 12:00:00";
				my $daysDifference = time::calculate_days_difference($symptomDatetime, $visitDatetime);
				if (!$symptomsBeforePCR) { # If symptomsBeforePCR = 0, skipping the symptoms which have occured before the PCR.
					next if $symptomCompdate < $visitCompdate; # Verify that the symptom have occured on the day or after the PCR.
				}
				next if $daysDifference > $daysOffset;
				# say "visitDate                   : $visitDate";
				# say "pcrResult                   : $pcrResult";
				# say "daysDifference              : $daysDifference";
				# die;
				$symptomsWithTest = 1;
				my $difToZero = abs(0 - $daysDifference);
				$closestDayFromSymptomToTest = $difToZero if $difToZero < $closestDayFromSymptomToTest;
				if ($pcrResult eq 'POS') {
					$hasSymptomsWithPositiveTest = 1;
					$lastCovidDate = $visitDate;
				}
				# say "$symptomDatetime -> $visitDate ($daysDifference days | $pcrResult)";
			}
			# say "symptomsWithTest         : $symptomsWithTest";
			# say "closestDayFromSymptomToTest : $closestDayFromSymptomToTest";
			if ($symptomsWithTest) {
				$hasSymptomsWithTest = 1;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsWithTest'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsWithTest'}->{'total'}++;
				die if $lastCovidDate && !$subjectsWithPCRs{$subjectId}->{'hasCovidWithSymptoms'};
			} else {
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsWithoutTest'}->{$randomizationGroup}++;
				$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsWithoutTest'}->{'total'}++;
			}
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{$randomizationGroup}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'symptoms'}->{'symptomsSets'}->{'total'}++;
		}
		if ($hasSymptomsWithTest) {
			$stats{'symptomsAnalysis'}->{'subjects'}->{'subjectsWithSymptomsAndTest'}->{$randomizationGroup}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'subjects'}->{'subjectsWithSymptomsAndTest'}->{'total'}++;
		}
		if ($hasSymptomsWithPositiveTest) {
			$stats{'symptomsAnalysis'}->{'subjects'}->{'subjectsWithSymptomsAndPositiveTest'}->{$randomizationGroup}->{'total'}++;
			$stats{'symptomsAnalysis'}->{'subjects'}->{'subjectsWithSymptomsAndPositiveTest'}->{'total'}++;
		}
	}
	close $out;
}
p%stats;
# p%weeklyStats;

open my $out2, '>:utf8', 'public/doc/pfizer_trials/subjects_with_pcr_and_symptoms.json';
say $out2 encode_json\%subjectsWithPCRs;
close $out2;

open my $out3, '>:utf8', 'weekly_cases_accrued.csv';
for my $label (sort keys %weeklyStats) {
	my ($bNT162b2, $placebo, $unknown) = (0, 0, 0);
	for my $weekNumber (sort{$a <=> $b} keys %{$weeklyStats{$label}}) {
		$bNT162b2 += $weeklyStats{$label}->{$weekNumber}->{'BNT162b2'} // 0;
		$placebo  += $weeklyStats{$label}->{$weekNumber}->{'Placebo'}  // 0;
		$unknown  += $weeklyStats{$label}->{$weekNumber}->{'Unknown'}  // 0;
		say $out3 "$label;$weekNumber;$bNT162b2;$placebo;$unknown;";
	}
}
close $out3;