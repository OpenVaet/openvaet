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
use Math::CDF;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use time;

# Treatment configuration.
my $daysOffset           = 5;
my $symptomsBeforePCR    = 1; # 0 = before non included ; 1 = before included.
my $officialSymptomsOnly = 0; # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.
my $cutoffCompdate       = '20211114';
my ($cY, $cM, $cD)       = $cutoffCompdate =~ /(....)(..)(..)/;
my $cutoffDatetime       = "$cY-$cM-$cD 12:00:00";
my $df                   = 1; # degrees of freedom

# Loading data required.
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $advaFile             = "public/doc/pfizer_trials/pfizer_adva_patients.json";

my %advaData             = ();
my %adsl                 = ();
load_adsl();
load_adva_data();

my %stats = ();

parse_data();

# Calculating averages of antibodies on each arm.
calculate_official_antibodies();
# Calculating averages of antibodies on each arm taking into account the hidden tests when there is one on a visit.
calculate_hidden_antibodies();
# Printing subject sample.
print_subject_sample();

# Priting end usage stats.
delete $stats{'totalSubjects'}->{'7_visitsByNums'};
delete $stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'};
p%stats;

sub load_adsl {
	open my $in, '<:utf8', $adslFile or die "Missing file [$adslFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adsl = %$json;
	say "[$adslFile] -> subjects : " . keys %adsl;
}

sub load_adva_data {
	open my $in, '<:utf8', $advaFile or die "Missing file [$advaFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%advaData = %$json;
	say "[$advaFile] -> patients : " . keys %advaData;
}

sub parse_data {
	open my $out, '>:utf8', 'subjects_50_titer_data.csv';
	for my $subjectId (sort{$a <=> $b} keys %adsl) {
		my ($trialSiteId)  = $subjectId =~ /^(....)....$/;
		my $aai1effl       = $adsl{$subjectId}->{'aai1effl'}       // die;
		my $mulenRfl       = $adsl{$subjectId}->{'mulenRfl'}       // die;
		my $phase          = $adsl{$subjectId}->{'phase'}          // die;
		my $saffl          = $adsl{$subjectId}->{'saffl'}          // die;
		my $ageYears       = $adsl{$subjectId}->{'ageYears'}       // die;
		my $arm            = $adsl{$subjectId}->{'arm'}            // die;
		my $hasHIV         = $adsl{$subjectId}->{'hasHIV'}         // die;
		my $uSubjectId     = $adsl{$subjectId}->{'uSubjectId'}     // die;
		my $unblindingDate = $adsl{$subjectId}->{'unblindingDate'} || $cutoffCompdate;
		my $cohort         = $adsl{$subjectId}->{'cohort'}         // die;
		my $sex            = $adsl{$subjectId}->{'sex'}            // die;

		# Verifying phase.
		next unless $phase eq 'Phase 1';
		$stats{'totalSubjects'}->{'1_totalPhase1'}++;
		next if $arm eq 'SCREEN FAILURE' || $arm eq 'NOT ASSIGNED';
		$stats{'totalSubjects'}->{'2_totalPhase1Randomized'}->{'total'}++;
		$stats{'totalSubjects'}->{'2_totalPhase1Randomized'}->{$arm}++;
		next if $cohort =~ /100mcg/;
		$stats{'totalSubjects'}->{'3_totalPhase1Not100mcg'}->{'total'}++;
		$stats{'totalSubjects'}->{'3_totalPhase1Not100mcg'}->{$arm}++;
		next if $arm eq 'Placebo';
		$stats{'totalSubjects'}->{'4_totalPhase1BNT162bX'}->{'total'}++;
		$stats{'totalSubjects'}->{'4_totalPhase1BNT162bX'}->{$arm}++;
		my $randomizationDatetime = $adsl{$subjectId}->{'randomizationDatetime'} // '';
		my $randomizationDate = $adsl{$subjectId}->{'randomizationDate'};
		# next if (!$randomizationDate || ($randomizationDate > $cutoffCompdate));

		# Verifying Dose 1.
		my $dose1Date     = $adsl{$subjectId}->{'dose1Date'};
		my $dose2Date     = $adsl{$subjectId}->{'dose2Date'};
		my $dose1Datetime = $adsl{$subjectId}->{'dose1Datetime'};
		my $dose2Datetime = $adsl{$subjectId}->{'dose2Datetime'};
		my $dose3Datetime = $adsl{$subjectId}->{'dose3Datetime'};

		next unless keys %{$advaData{$subjectId}};
		$stats{'totalSubjects'}->{'5_totalPhase1BNTAdva'}->{'total'}++;
		$stats{'totalSubjects'}->{'5_totalPhase1BNTAdva'}->{$arm}++;
		for my $visitName (sort keys %{$advaData{$subjectId}->{'visits'}}) {
			my $visitDay  = visit_name_to_day($visitName);
			my $visitDate = $advaData{$subjectId}->{'visits'}->{$visitName}->{'visitDate'} // die;
			my $hasTest   = 0;
			for my $testName (sort keys %{$advaData{$subjectId}->{'visits'}->{$visitName}->{'tests'}}) {
				if ($testName eq 'SARS-CoV-2 serum neutralizing titer 50 (titer) - Virus Neutralization Assay') {
					my @results = @{$advaData{$subjectId}->{'visits'}->{$visitName}->{'tests'}->{$testName}};

					# Incrementing data for the official stats.
					for my $resultData (@results) {
						my $result    = %$resultData{'avaLc'}     // die;
						my $aVisit    = %$resultData{'aVisit'}    // die;
						my $aVisitNum = %$resultData{'aVisitNum'} // die;
						($aVisitNum)  = split '\.', $aVisitNum;
						$hasTest++;
						$stats{'totalSubjects'}->{'6_visitsByNames'}->{$visitName}->{'aVisit'} = $aVisit;
						$stats{'totalSubjects'}->{'6_visitsByNames'}->{$visitName}->{'aVisitNum'} = $aVisitNum;
						unless ($aVisit) {
							# say "*" x 50;
							# say "subjectId : $subjectId";
							# p$advaData{$subjectId}->{'visits'};
							$stats{'totalSubjects'}->{'6_visitsByNames'}->{$visitName}->{'noAVISITSkipped'}++;
							next;
						}
						$stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$aVisitNum}->{'aVisit'} = $aVisit;
						$stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$aVisitNum}->{'visitName'} = $visitName;
						$stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$aVisitNum}->{'totalAntibodies'}+= $result;
						$stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$aVisitNum}->{'totalVisits'}++;
					}

					# Incrementing data for the "hidden measurements" included angle.
					if (scalar @results == 2) {
						for my $resultData (@results) {
							my $result    = %$resultData{'avaLc'}  // die;
							my $aVisit    = %$resultData{'aVisit'} // die;
							if ($aVisit) {
								$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodiesOfficial'}+= $result;
							} else {
								# say "result : $result";
								$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'visitName'} = $visitName;
								$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodies'}+= $result;
								$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalVisits'}++;
							}
						}
					} else { # Otherwise picking the only test.
						for my $resultData (@results) {
							my $result    = %$resultData{'avaLc'}     // die;
							my $aVisit    = %$resultData{'aVisit'} // die;
							$hasTest++;
							die unless ($aVisit);
							$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodiesOfficial'}+= $result;
							$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'visitName'} = $visitName;
							$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodies'}+= $result;
							$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalVisits'}++;
						}
					}

					# Printing individual offsets (if two tests) & flatten data.
					my %r1 = %{$results[0]};
					my %r2 = ();
					my ($avaLc1, $avisit, $aVisitNum);
					my $avaLc2 = '';
					if ($results[1]) {
						%r2 = %{$results[1]};
						# p%r2;
						# die;
					}
					# p%r1;
					# die;
					# p@results;
					# die;
				}
			}
			$stats{'totalSubjects'}->{'6_visitsByNames'}->{$visitName}->{'totalVisits'}++ if $hasTest;
		}
	}
}

sub calculate_official_antibodies {
	open my $out, '>:utf8', 'antibodies_mean_average_by_visit_num.csv';
	say $out "Treatment Arm;Visit Num;Visit Name;AVisit;Days post Dose 1;Total Antibodies;Total Visits;Average Antibodies By Subject;";
	for my $arm (sort keys %{$stats{'totalSubjects'}->{'7_visitsByNums'}}) {
		for my $visitNum (sort{$a <=> $b} keys %{$stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}}) {
			my $totalAntibodies = $stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$visitNum}->{'totalAntibodies'} // die;
			my $totalVisits     = $stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$visitNum}->{'totalVisits'}     // die;
			my $visitName       = $stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$visitNum}->{'visitName'}       // die;
			my $visitDay        = visit_name_to_day($visitName);
			my $aVisit          = $stats{'totalSubjects'}->{'7_visitsByNums'}->{$arm}->{$visitNum}->{'aVisit'}          // die;
			my $avgAntiBBySub   = nearest(0.01, $totalAntibodies / $totalVisits);
			if ($arm eq 'BNT162b2 Phase 1 (30 mcg)') {
				say $out "$arm;$visitNum;$visitName;$aVisit;$visitDay;$totalAntibodies;$totalVisits;$avgAntiBBySub";
			}
		}
	}
	close $out;
}

sub calculate_hidden_antibodies {
	open my $out, '>:utf8', 'antibodies_mean_average_by_visit_num_with_hidden_test.csv';
	say $out "Treatment Arm;Visit Name;Days post Dose 1;Total Antibodies;Total Visits;Average Antibodies By Subject;Official Average Antibodies By Subject;";
	for my $arm (sort keys %{$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}}) {
		for my $visitDay (sort{$a <=> $b} keys %{$stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}}) {
			my $totalAntibodiesOfficial = $stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodiesOfficial'} // die;
			my $totalAntibodies         = $stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalAntibodies'}         // die;
			my $totalVisits             = $stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'totalVisits'}             // die;
			my $visitName               = $stats{'totalSubjects'}->{'8_visitsByNumsWithHiddenTests'}->{$arm}->{$visitDay}->{'visitName'}               // die;
			my $visitDay                = visit_name_to_day($visitName);
			my $avgAntiBBySub           = nearest(0.01, $totalAntibodies / $totalVisits);
			my $avgAntiBBySubOffi       = nearest(0.01, $totalAntibodiesOfficial / $totalVisits);
			if ($arm eq 'BNT162b2 Phase 1 (30 mcg)') {
				say $out "$arm;$visitName;$visitDay;$totalAntibodies;$totalVisits;$avgAntiBBySub;$avgAntiBBySubOffi;";
			}
		}
	}
	close $out;
}

sub print_subject_sample {
	open my $out, '>:utf8', '10071066_records_sample.csv';
	say $out "VISIT;ISDTC;AVISIT;AVALC;";
	for my $visitName (sort keys %{$advaData{'10071066'}->{'visits'}}) {
		my ($visitDate) = split ' ', $advaData{'10071066'}->{'visits'}->{$visitName}->{'visitDatetime'};
		for my $testData (@{$advaData{'10071066'}->{'visits'}->{$visitName}->{'tests'}->{'SARS-CoV-2 serum neutralizing titer 50 (titer) - Virus Neutralization Assay'}}) {
			my $avaLc = %$testData{'avaLc'} // die;
			my $aVisit = %$testData{'aVisit'} // '';
			say $out "$visitName;$visitDate;$aVisit;$avaLc;";
		}
	}
	close $out;
}

sub visit_name_to_day {
	my $visitName = shift;
	my $visitDay;
	if ($visitName eq 'V1_DAY1_VAX1_S') {
		$visitDay = 1;
	} elsif ($visitName eq 'V3_WEEK1_POSTVAX1_S') {
		$visitDay = 7;
	} elsif ($visitName eq 'V4_WEEK3_VAX2_S') {
		$visitDay = 21;
	} elsif ($visitName eq 'V5_WEEK1_POSTVAX2_S') {
		$visitDay = 28;
	} elsif ($visitName eq 'V6_WEEK2_POSTVAX2_S') {
		$visitDay = 35;
	} elsif ($visitName eq 'V7_MONTH1_S') {
		$visitDay = 49;
	} elsif ($visitName eq 'V8_MONTH6_S') {
		$visitDay = 183;
	} else {
		die "visitName: [$visitName]";
	}
	return $visitDay;
}