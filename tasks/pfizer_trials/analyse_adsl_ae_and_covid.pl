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
use File::Path qw(make_path);
use time;

# Treatment configuration.
my $symptomsIncluded     = 1;   # 0 = no symptoms, 1 = symptoms.
my $officialSymptomsOnly = 0;   # 0 = secondary symptoms taken into account ; 1 = secondary symptoms included.
my $toxicityGradeDetails = 0;   # Either 0 or 1 (1 = with grade details).
my $csvSeparator         = ';'; # Whichever char is best for your OS localization.
my $cutoffCompdate       = '20210313';
my ($cY, $cM, $cD)       = $cutoffCompdate =~ /(....)(..)(..)/;
my $cutoffDatetime       = "$cY-$cM-$cD 12:00:00";
my $doseCutoffCompdate   = '20201018';
my ($dCY, $dCM, $dCD)    = $doseCutoffCompdate =~ /(....)(..)(..)/;
my $doseCutoffDatetime   = "$dCY-$dCM-$dCD 12:00:00";
my $doseFromCompdate     = '20201019';
my ($dFY, $dFM, $dFD)    = $doseFromCompdate =~ /(....)(..)(..)/;
my $doseFromDatetime     = "$dFY-$dFM-$dFD 12:00:00";

# Loading data required.
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $adaeFile             = 'public/doc/pfizer_trials/pfizer_adae_patients.json';
my $advaFile             = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $pcrRecordsFile       = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $faceFile             = 'public/doc/pfizer_trials/pfizer_face_patients.json';
my $symptomsFile         = 'public/doc/pfizer_trials/pfizer_patients_symptoms.json';
my $testsRefsFile        = 'public/doc/pfizer_trials/pfizer_di.json';

my %adsl                 = ();
my %adaes                = ();
my %advaData             = ();
my %faces                = ();
my %pcrRecords           = ();
my %symptoms             = ();
my %testsRefs            = ();
load_adsl();
load_adae();
load_adva();
load_faces();
load_symptoms();
load_pcr_tests();
load_tests_refs();

my %stats       = ();
my %genStats    = ();
my %subjectsAEs = ();
my ($current, $total) = (0, 0);
$total = keys %adsl;
for my $subjectId (sort{$a <=> $b} keys %adsl) {
	$current++;
	# last if $current > 5000;
	STDOUT->printflush("\rParsing subjects data - [$current / $total]");
	my $trialSiteId    = $adsl{$subjectId}->{'trialSiteId'}    // die;
	my $aai1effl       = $adsl{$subjectId}->{'aai1effl'}       // die;
	my $mulenRfl       = $adsl{$subjectId}->{'mulenRfl'}       // die;
	my $phase          = $adsl{$subjectId}->{'phase'}          // die;
	my $saffl          = $adsl{$subjectId}->{'saffl'}          // die;
	my $ageYears       = $adsl{$subjectId}->{'ageYears'}       // die;
	next unless $ageYears >= 16;
	my $ageGroup       = age_to_age_group($ageYears);
	my $arm            = $adsl{$subjectId}->{'arm'}            // die;
	my $hasHIV         = $adsl{$subjectId}->{'hasHIV'}         // die;
	my $uSubjectId     = $adsl{$subjectId}->{'uSubjectId'}     // die;
	my $unblindingDate = $adsl{$subjectId}->{'unblindingDate'} || $cutoffCompdate;
	my $deathDatetime  = $adsl{$subjectId}->{'deathDatetime'};
	my $deathCompdate;
	my $limitDate = $cutoffCompdate;
	if ($deathDatetime) {
		($deathCompdate) = split ' ', $deathDatetime;
		$deathCompdate =~ s/\D//g;
		die if $deathCompdate && ($deathCompdate > 20210313);
		$limitDate = $deathCompdate;
	}

	# Verifying phase data (only phase 1 30 mcg are kept).
	unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
		unless (exists $advaData{$subjectId}) {
			next;
		}
		my $actArm = $advaData{$subjectId}->{'actArm'}         // die;
		next if $actArm ne 'BNT162b2 Phase 1 (30 mcg)';
	}
	my $sex                   = $adsl{$subjectId}->{'sex'}     // die;

	# Fetching Doses received & randomization data.
	my $dose1Date             = $adsl{$subjectId}->{'dose1Date'};
	my $dose1Datetime         = $adsl{$subjectId}->{'dose1Datetime'};
	next unless $dose1Datetime;
	my $randomizationDatetime = $adsl{$subjectId}->{'randomizationDatetime'} // '';
	my $randomizationDate     = $adsl{$subjectId}->{'randomizationDate'};
	my $dose2Date             = $adsl{$subjectId}->{'dose2Date'};
	my $dose2Datetime         = $adsl{$subjectId}->{'dose2Datetime'};
	my $dose3Date             = $adsl{$subjectId}->{'dose3Date'};
	my $dose3Datetime         = $adsl{$subjectId}->{'dose3Datetime'};
	my $dose4Date             = $adsl{$subjectId}->{'dose4Date'};
	my $dose4Datetime         = $adsl{$subjectId}->{'dose4Datetime'};
	my $covidAtBaseline       = $adsl{$subjectId}->{'covidAtBaseline'}       // die;

	# Reorganizing symptoms by dates.
	my ($hasSymptoms, %symptomsByVisit) = subject_symptoms_by_visits($subjectId);

	# Verifying Visit 1 Tests.
	my ($hasPositiveCentralPCR,
		%centralPCRsByVisits)           = subject_central_pcrs_by_visits($subjectId);
	my ($hasPositiveLocalPCR,
		%localPCRsByVisits)             = subject_local_pcrs_by_visits($subjectId);
	my $nBindingAntibodyAssayV1         = $advaData{$subjectId}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'} // 'MIS';
	my $centralNAATV1                   = $centralPCRsByVisits{'V1_DAY1_VAX1_L'}->{'pcrResult'} // 'MIS';

	# Setting Covid at baseline own tags.
	my ($covidAtBaselineRecalc, $covidAtBaselineRecalcSource) = (0, undef);
	if ($nBindingAntibodyAssayV1 eq 'POS' || $centralNAATV1 eq 'POS') {
		$genStats{'covidAtBaselineNoTagStats'}->{$covidAtBaseline}++ if $covidAtBaseline ne 'POS';
		$covidAtBaselineRecalc = 1;
		if ($nBindingAntibodyAssayV1 eq 'POS' && $centralNAATV1 eq 'POS') {
			$covidAtBaselineRecalcSource = 'NAAT + NBinding';
		} else {
			$covidAtBaselineRecalcSource = 'NBinding' if $nBindingAntibodyAssayV1 eq 'POS';
			$covidAtBaselineRecalcSource = 'NAAT'     if $centralNAATV1           eq 'POS';
		}
	}
	if ($covidAtBaseline eq 'POS') {
		unless ($nBindingAntibodyAssayV1 eq 'POS' || $centralNAATV1 eq 'POS') {
			for my $label (sort keys %{$advaData{$subjectId}}) {
				delete $advaData{$subjectId}->{$label} unless $label eq 'visits';
			}
			for my $label (sort keys %{$pcrRecords{$subjectId}}) {
				delete $pcrRecords{$subjectId}->{$label} unless $label eq 'mbVisits';
			}
			# say '';
			# say "*" x 50;
			# say "*" x 50;
			# say "subjectId                : $subjectId";
			# say "trialSiteId              : $trialSiteId";
			# say "arm                      : $arm";
			# say "randomizationDatetime    : $randomizationDatetime";
			# say "covidAtBaseline          : $covidAtBaseline";
			# say "dose1Datetime            : $dose1Datetime";
			# say "dose2Datetime            : $dose2Datetime";
			# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
			# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
			# say "centralNAATV1            : [$centralNAATV1]";
			# say "local                    :";

			# p%localPCRsByVisits;
			# say "central                  :";
			# p%centralPCRsByVisits;
			# say "symptoms                 :";
			# p%symptomsByVisit;
			# say "adva                     :";
			# p$advaData{$subjectId};
			# say "pcrs                     :";
			# p$pcrRecords{$subjectId};
			$genStats{'covidAtBaselineAnomalies'}->{$arm}++;
			$genStats{'covidAtBaselineNoTestStats'}->{$covidAtBaseline}++;
		}

		# Setting Covid at baseline tag if unset so far.
		unless ($covidAtBaselineRecalc) {
			$covidAtBaselineRecalc = 1;
			$covidAtBaselineRecalcSource = 'Baseline tag';
		}
	} elsif ($covidAtBaseline eq 'NEG') {
		# Nothing to do.
	} elsif ($covidAtBaseline eq '') {
		# Nothing to do.
	} else {
		die "covidAtBaseline : [$covidAtBaseline]";
	}

	# Organizing doses received in a hashtable allowing easy numerical sorting.
	my %doseDates = ();
	$doseDates{'1'} = $dose1Datetime;
	$doseDates{'2'} = $dose2Datetime if $dose2Datetime;
	$doseDates{'3'} = $dose3Datetime if $dose3Datetime;
	$doseDates{'4'} = $dose4Datetime if $dose4Datetime;

	# If the subject had Covid at baseline he will be accruing time only for the "infected prior dose" group.
	if ($covidAtBaselineRecalc) {

		# Setting values related to subject's populations.
		my ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate) = time_of_exposure_from_simple($arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose1Date, $dose2Date, $dose3Date, $deathDatetime, $deathCompdate);
		# say '';
		# say "*" x 50;
		# say "*" x 50;
		# say "subjectId                : $subjectId";
		# say "trialSiteId              : $trialSiteId";
		# say "arm                      : $arm";
		# say "randomizationDatetime    : $randomizationDatetime";
		# say "covidAtBaseline          : $covidAtBaseline";
		# say "dose1Datetime            : $dose1Datetime";
		# say "dose2Datetime            : $dose2Datetime";
		# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
		# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
		# say "centralNAATV1            : [$centralNAATV1]";
		# say "local                    :";
		# p%localPCRsByVisits;
		# say "central                  :";
		# p%centralPCRsByVisits;
		# say "symptoms                 :";
		# p%symptomsByVisit;
		# say "limitDate                : $limitDate";
		# say "doeBNT162b2              : $doeBNT162b2";
		# say "doePlacebo               : $doePlacebo";
		# say "doePlaceboToBNT162b2     : $doePlaceboToBNT162b2";

		# Once done with all the required filterings, incrementing stats.
		# Population stats.
		# Total Subjects
		$stats{'Doses Post Infection'}->{$ageGroup}->{'totalSubjects'}++;
		# Subject's Arm.
		$stats{'Doses Post Infection'}->{$ageGroup}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
		if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
			$stats{'Doses Post Infection'}->{$ageGroup}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
		}
		# Days of exposure for each arm.
		$stats{'Doses Post Infection'}->{$ageGroup}->{'doePlaceboToBNT162b2'} += $doePlaceboToBNT162b2;
		$stats{'Doses Post Infection'}->{$ageGroup}->{'doeBNT162b2'}          += $doeBNT162b2;
		$stats{'Doses Post Infection'}->{$ageGroup}->{'doePlacebo'}           += $doePlacebo;

		# AE stats.
		my ($hasAE, $hasSAE) = (0, 0);
		if (exists $adaes{$subjectId}) {
			# For each date on which AEs have been reported
			for my $aeCompdate (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
				my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
				die unless ($aeY && $aeM && $aeD);
				# Skipping AE if observed after cut-off.
				next if $aeCompdate > $treatmentCutoffCompdate;
				my %doseDatesByDates = ();
				for my $dNum (sort{$a <=> $b} keys %doseDates) {
					my $dt = $doseDates{$dNum} // die;
					my ($cpDt) = split ' ', $dNum;
					$cpDt =~ s/\D//g;
					next unless $cpDt < $aeCompdate;
					my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
					$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
					$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
				}
				my ($closestDoseDate, $closestDose, $doseToAEDays);
				for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
					$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
					$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
					$doseToAEDays    = $daysBetween;
					last;
				}
				my ($closestDoseCompdate) = split ' ', $closestDoseDate;
				$closestDoseCompdate =~ s/\D//g;
				my $doseArm = $arm;
				if ($arm ne 'Placebo') {
					$doseArm = 'BNT162b2 (30 mcg)';
				}
				if ($closestDose > 2) {
					$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
				}
				# say "*" x 50;
				# say "aeCompdate               : $aeCompdate";
				# say "closestDoseDate          : $closestDoseDate";
				# say "closestDose              : $closestDose";
				# say "doseToAEDays             : $doseToAEDays";
				# say "doseArm                  : $doseArm";

				# For Each adverse effect reported on this date.
				for my $aeObserved (sort keys %{$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}}) {
					# p$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved};die;
					my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
					# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
					my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
					my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
					my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
					if ($aeser eq 'Y') {
						$aeser  = 1;
						$hasSAE = 1;
					} elsif ($aeser eq 'N') {
						$aeser = 0;
					} else {
						$aeser = 0;
					}
					$hasAE = 1;
					# say "*" x 50;
					# say "aehlgt                   : $aehlgt";
					# say "aehlt                    : $aehlt";
					# say "aeser                    : $aeser";
					# say "toxicityGrade            : $toxicityGrade";
					# die;

					# Grade level - global stat & by toxicity stats.
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
					if ($aeser) {
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
					}

					# Category level - stats & by toxicity stats
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
					if ($aeser) {
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
					}

					# Reaction level - stats & by toxicity stats. 
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
						$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
					}
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
					$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
					if ($aeser) {
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
						$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
						unless (exists $subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
							$subjectsAEs{'Doses Post Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
							$stats{'Doses Post Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
						}
					}
				}
			}
		}
		# Total subjects with AE.
		if ($hasAE) {
			$stats{'Doses Post Infection'}->{$ageGroup}->{'totalSubjectsWithAE'}++;
		}
		# Total subjects with SAE.
		if ($hasSAE) {
			$stats{'Doses Post Infection'}->{$ageGroup}->{'totalSubjectsWithSAEs'}++;
		}
	} else {
		# If not he will be accruing time of exposure for the "non infected group"
		# up to his infection if it occures before dose 2, 3 or 4
		my $hasInfection  = 0;
		if ($hasPositiveCentralPCR || $hasSymptoms) {
			if ($symptomsIncluded) {
				$hasInfection = 1;
			} else {
				$hasInfection = 1 if $hasPositiveCentralPCR;
			}
		}
		if ($hasInfection) {
			my $earliestCovid = 99999999;
			my $earliestVisit;
			if ($hasPositiveCentralPCR && $hasSymptoms) {
				# say "1";
				for my $covidVisit (sort keys %centralPCRsByVisits) {
					my $visitDate = $centralPCRsByVisits{$covidVisit}->{'visitDate'} // die;
					my $pcrResult = $centralPCRsByVisits{$covidVisit}->{'pcrResult'} // die;
					if ($pcrResult eq 'POS') {
						my $compDate  = $visitDate;
						$compDate     =~ s/\D//g;
						if ($compDate < $earliestCovid) {
							$earliestCovid = $compDate;
							$earliestVisit = $covidVisit;
						}
					}
				}

				# Earliest symptom date corresponding to visit.
				# p$symptomsByVisit{$earliestVisit};
				# die;
				my $symptomDate = $symptomsByVisit{$earliestVisit}->{'symptomDate'};
				if ($symptomDate) {
					my $symptomComp = $symptomDate;
					$symptomComp    =~ s/\D//g;
					$earliestCovid  = $symptomComp if ($symptomComp < $earliestCovid);
				}
			} else {
				if ($hasPositiveCentralPCR) {
					# say "2";
					for my $covidVisit (sort keys %centralPCRsByVisits) {
						my $visitDate = $centralPCRsByVisits{$covidVisit}->{'visitDate'} // die;
						my $pcrResult = $centralPCRsByVisits{$covidVisit}->{'pcrResult'} // die;
						if ($pcrResult eq 'POS') {
							my $compDate  = $visitDate;
							$compDate     =~ s/\D//g;
							if ($compDate < $earliestCovid) {
								$earliestCovid = $compDate;
								$earliestVisit = $covidVisit;
							}
						}
					}
				} else {
					# say "3";
					for my $covidVisit (sort keys %symptomsByVisit) {
						my $symptomDate = $symptomsByVisit{$covidVisit}->{'symptomDate'} // die;
						# say "symptomDate : $symptomDate";
						my $compDate  = $symptomDate;
						$compDate     =~ s/\D//g;
						if ($compDate < $earliestCovid) {
							$earliestCovid = $compDate;
							$earliestVisit = $covidVisit;
						}
					}
				}
			}
			die unless $earliestCovid;
			my $latestDoseDatetime;
			for my $doseNum (sort{$b <=> $a} keys %doseDates) {
				$latestDoseDatetime = $doseDates{$doseNum} // die;
				last;
			}
			my ($latestDoseDate) = split ' ', $latestDoseDatetime;
			$latestDoseDate =~ s/\D//g;

			if ($earliestCovid < $latestDoseDate) {
				# COVID prior last dose, so the subject will accrue time in both groups.
				# say '';
				# say "*" x 50;
				# say "*" x 50;
				# say "subjectId                : $subjectId";
				# say "trialSiteId              : $trialSiteId";
				# say "arm                      : $arm";
				# say "randomizationDatetime    : $randomizationDatetime";
				# say "covidAtBaseline          : $covidAtBaseline";
				# say "dose1Datetime            : $dose1Datetime";
				# say "dose2Datetime            : $dose2Datetime";
				# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
				# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
				# say "centralNAATV1            : [$centralNAATV1]";
				# say "local                    :";
				# p%localPCRsByVisits;
				# say "central                  :";
				# p%centralPCRsByVisits;
				# say "symptoms                 :";
				# p%symptomsByVisit;
				# say "limitDate                : $limitDate";
				# say "hasSymptoms              : $hasSymptoms";
				# say "hasPositiveCentralPCR    : $hasPositiveCentralPCR";
				# say "earliestCovid            : $earliestCovid";
				# say "earliestVisit            : $earliestVisit";
				# say "latestDoseDatetime       : $latestDoseDatetime";
				# say "latestDoseDate           : $latestDoseDate";
				my $lastDosePriorCovidDate = 99999999;
				my $lastDosePriorCovid;
				for my $doseNum (sort{$b <=> $a} keys %doseDates) {
					my $doseDatetime = $doseDates{$doseNum} // die;
					my ($latestDoseDate) = split ' ', $doseDatetime;
					$latestDoseDate =~ s/\D//g;
					$lastDosePriorCovidDate = $latestDoseDate;
					$lastDosePriorCovid = $doseNum;
					last if $latestDoseDate < $earliestCovid;
				}
				die unless $lastDosePriorCovid;
				my ($lDY, $lDM, $lDD) = $lastDosePriorCovidDate =~ /(....)(..)(..)/;
				my $lastDosePriorCovidDatetime = "$lDY-$lDM-$lDD 12:00:00";
				# say "lastDosePriorCovidDate   : $lastDosePriorCovidDate";
				# say "lastDosePriorCovid       : $lastDosePriorCovid";

				# From first dose, to dose post infection, subject counts as "without infection".
				# Then he counts as "post infection".
				my @labels = ('Doses Without Infection', 'Doses Post Infection');
				for my $label (@labels) {
					# Normal scenario - Covid post exposure.
					# Setting values related to subject's populations.
					my ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate) = time_of_exposure_from_conflicting($label, $arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose4Datetime, $dose1Date, $dose2Date, $dose3Date, $dose4Date, $deathDatetime, $deathCompdate, $lastDosePriorCovidDatetime, $lastDosePriorCovidDate, $lastDosePriorCovid, $earliestCovid);
					# say '';
					# say "*" x 50;
					# say "*" x 50;
					# say "subjectId                : $subjectId";
					# say "trialSiteId              : $trialSiteId";
					# say "arm                      : $arm";
					# say "randomizationDatetime    : $randomizationDatetime";
					# say "covidAtBaseline          : $covidAtBaseline";
					# say "dose1Datetime            : $dose1Datetime";
					# say "dose2Datetime            : $dose2Datetime";
					# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
					# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
					# say "centralNAATV1            : [$centralNAATV1]";
					# say "local                    :";
					# p%localPCRsByVisits;
					# say "central                  :";
					# p%centralPCRsByVisits;
					# say "symptoms                 :";
					# p%symptomsByVisit;
					# say "limitDate                : $limitDate";
					# say "doeBNT162b2              : $doeBNT162b2";
					# say "doePlacebo               : $doePlacebo";
					# say "doePlaceboToBNT162b2     : $doePlaceboToBNT162b2";
					# say "$groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate";
					die unless $doeBNT162b2 || $doePlacebo || $doePlaceboToBNT162b2;

					# Once done with all the required filterings, incrementing stats.
					# Population stats.
					# Total Subjects
					$stats{$label}->{$ageGroup}->{'totalSubjects'}++;
					# Subject's Arm.
					$stats{$label}->{$ageGroup}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
					if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
						$stats{$label}->{$ageGroup}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
					}
					# Days of exposure for each arm.
					$stats{$label}->{$ageGroup}->{'doePlaceboToBNT162b2'} += $doePlaceboToBNT162b2;
					$stats{$label}->{$ageGroup}->{'doeBNT162b2'}          += $doeBNT162b2;
					$stats{$label}->{$ageGroup}->{'doePlacebo'}           += $doePlacebo;

					# AE stats.
					my ($hasAE, $hasSAE) = (0, 0);
					if (exists $adaes{$subjectId}) {
						# For each date on which AEs have been reported
						for my $aeCompdate (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
							my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
							die unless ($aeY && $aeM && $aeD);
							# Skipping AE if observed after cut-off.
							next if $aeCompdate > $treatmentCutoffCompdate;
							my %doseDatesByDates = ();
							for my $dNum (sort{$a <=> $b} keys %doseDates) {
								my $dt = $doseDates{$dNum} // die;
								my ($cpDt) = split ' ', $dNum;
								$cpDt =~ s/\D//g;
								next unless $cpDt < $aeCompdate;
								my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
								$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
								$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
							}
							my ($closestDoseDate, $closestDose, $doseToAEDays);
							for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
								$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
								$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
								$doseToAEDays    = $daysBetween;
								last;
							}

							# Filtering AE based on label & closest dose.
							if ($label eq 'Doses Post Infection') {
								next if $closestDose <= $lastDosePriorCovid;
								# say "closestDose        : $closestDose";
								# say "lastDosePriorCovid : $lastDosePriorCovid";
								# die;
							} elsif ($label eq 'Doses Without Infection') {
								next if $closestDose > $lastDosePriorCovid;
								# say "closestDose        : $closestDose";
								# say "lastDosePriorCovid : $lastDosePriorCovid";
								# die;
							} else {
								# say "closestDose        : $closestDose";
								# say "lastDosePriorCovid : $lastDosePriorCovid";
								# die;
							}
							my ($closestDoseCompdate) = split ' ', $closestDoseDate;
							$closestDoseCompdate =~ s/\D//g;
							my $doseArm = $arm;
							if ($arm ne 'Placebo') {
								$doseArm = 'BNT162b2 (30 mcg)';
							}
							if ($closestDose > 2) {
								$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
							}
							# say "*" x 50;
							# say "aeCompdate               : $aeCompdate";
							# say "closestDoseDate          : $closestDoseDate";
							# say "closestDose              : $closestDose";
							# say "doseToAEDays             : $doseToAEDays";
							# say "doseArm                  : $doseArm";

							# For Each adverse effect reported on this date.
							for my $aeObserved (sort keys %{$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}}) {
								# p$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved};die;
								my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
								# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
								my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
								my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
								my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
								if ($aeser eq 'Y') {
									$aeser  = 1;
									$hasSAE = 1;
								} elsif ($aeser eq 'N') {
									$aeser = 0;
								} else {
									$aeser = 0;
								}
								$hasAE = 1;
								# say "*" x 50;
								# say "aehlgt                   : $aehlgt";
								# say "aehlt                    : $aehlt";
								# say "aeser                    : $aeser";
								# say "toxicityGrade            : $toxicityGrade";
								# die;

								# Grade level - global stat & by toxicity stats.
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
								if ($aeser) {
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
								}

								# Category level - stats & by toxicity stats
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
								if ($aeser) {
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
								}

								# Reaction level - stats & by toxicity stats. 
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
									$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
								}
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
								$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
								if ($aeser) {
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
									$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
									unless (exists $subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
										$subjectsAEs{$label}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
										$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
									}
								}
							}
						}
					}
					# Total subjects with AE.
					if ($hasAE) {
						$stats{$label}->{$ageGroup}->{'totalSubjectsWithAE'}++;
					}
					# Total subjects with SAE.
					if ($hasSAE) {
						$stats{$label}->{$ageGroup}->{'totalSubjectsWithSAEs'}++;
					}
					if ($label eq 'Doses Without Infection') {
					} else {

					}
				}
				# p%doseDates;
				# die;
			} else {
				# Normal scenario - Covid post exposure.
				# Setting values related to subject's populations.
				my ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate) = time_of_exposure_from_simple($arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose1Date, $dose2Date, $dose3Date, $deathDatetime, $deathCompdate);
				# say '';
				# say "*" x 50;
				# say "*" x 50;
				# say "subjectId                : $subjectId";
				# say "trialSiteId              : $trialSiteId";
				# say "arm                      : $arm";
				# say "randomizationDatetime    : $randomizationDatetime";
				# say "covidAtBaseline          : $covidAtBaseline";
				# say "dose1Datetime            : $dose1Datetime";
				# say "dose2Datetime            : $dose2Datetime";
				# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
				# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
				# say "centralNAATV1            : [$centralNAATV1]";
				# say "local                    :";
				# p%localPCRsByVisits;
				# say "central                  :";
				# p%centralPCRsByVisits;
				# say "symptoms                 :";
				# p%symptomsByVisit;
				# say "limitDate                : $limitDate";
				# say "doeBNT162b2              : $doeBNT162b2";
				# say "doePlacebo               : $doePlacebo";
				# say "doePlaceboToBNT162b2     : $doePlaceboToBNT162b2";

				# Once done with all the required filterings, incrementing stats.
				# Population stats.
				# Total Subjects
				$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjects'}++;
				# Subject's Arm.
				$stats{'Doses Without Infection'}->{$ageGroup}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
				if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
					$stats{'Doses Without Infection'}->{$ageGroup}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
				}
				# Days of exposure for each arm.
				$stats{'Doses Without Infection'}->{$ageGroup}->{'doePlaceboToBNT162b2'} += $doePlaceboToBNT162b2;
				$stats{'Doses Without Infection'}->{$ageGroup}->{'doeBNT162b2'}          += $doeBNT162b2;
				$stats{'Doses Without Infection'}->{$ageGroup}->{'doePlacebo'}           += $doePlacebo;

				# AE stats.
				my ($hasAE, $hasSAE) = (0, 0);
				if (exists $adaes{$subjectId}) {
					# For each date on which AEs have been reported
					for my $aeCompdate (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
						my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
						die unless ($aeY && $aeM && $aeD);
						# Skipping AE if observed after cut-off.
						next if $aeCompdate > $treatmentCutoffCompdate;
						my %doseDatesByDates = ();
						for my $dNum (sort{$a <=> $b} keys %doseDates) {
							my $dt = $doseDates{$dNum} // die;
							my ($cpDt) = split ' ', $dNum;
							$cpDt =~ s/\D//g;
							next unless $cpDt < $aeCompdate;
							my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
							$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
							$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
						}
						my ($closestDoseDate, $closestDose, $doseToAEDays);
						for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
							$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
							$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
							$doseToAEDays    = $daysBetween;
							last;
						}
						my ($closestDoseCompdate) = split ' ', $closestDoseDate;
						$closestDoseCompdate =~ s/\D//g;
						my $doseArm = $arm;
						if ($arm ne 'Placebo') {
							$doseArm = 'BNT162b2 (30 mcg)';
						}
						if ($closestDose > 2) {
							$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
						}
						# say "*" x 50;
						# say "aeCompdate               : $aeCompdate";
						# say "closestDoseDate          : $closestDoseDate";
						# say "closestDose              : $closestDose";
						# say "doseToAEDays             : $doseToAEDays";
						# say "doseArm                  : $doseArm";

						# For Each adverse effect reported on this date.
						for my $aeObserved (sort keys %{$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}}) {
							# p$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved};die;
							my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
							# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
							my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
							my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
							my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
							if ($aeser eq 'Y') {
								$aeser  = 1;
								$hasSAE = 1;
							} elsif ($aeser eq 'N') {
								$aeser = 0;
							} else {
								$aeser = 0;
							}
							$hasAE = 1;
							# say "*" x 50;
							# say "aehlgt                   : $aehlgt";
							# say "aehlt                    : $aehlt";
							# say "aeser                    : $aeser";
							# say "toxicityGrade            : $toxicityGrade";
							# die;

							# Grade level - global stat & by toxicity stats.
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
							if ($aeser) {
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
							}

							# Category level - stats & by toxicity stats
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
							if ($aeser) {
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
							}

							# Reaction level - stats & by toxicity stats. 
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
							}
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
							if ($aeser) {
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
								unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
									$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
									$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
								}
							}
						}
					}
				}
				# Total subjects with AE.
				if ($hasAE) {
					$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjectsWithAE'}++;
				}
				# Total subjects with SAE.
				if ($hasSAE) {
					$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjectsWithSAEs'}++;
				}
			}
		} else {

			# Setting values related to subject's populations.
			my ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate) = time_of_exposure_from_simple($arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose1Date, $dose2Date, $dose3Date, $deathDatetime, $deathCompdate);
			# say '';
			# say "*" x 50;
			# say "*" x 50;
			# say "subjectId                : $subjectId";
			# say "trialSiteId              : $trialSiteId";
			# say "arm                      : $arm";
			# say "randomizationDatetime    : $randomizationDatetime";
			# say "covidAtBaseline          : $covidAtBaseline";
			# say "dose1Datetime            : $dose1Datetime";
			# say "dose2Datetime            : $dose2Datetime";
			# say "dose3Datetime            : $dose3Datetime" if $dose3Datetime;
			# say "nBindingAntibodyAssayV1  : [$nBindingAntibodyAssayV1]";
			# say "centralNAATV1            : [$centralNAATV1]";
			# say "local                    :";
			# p%localPCRsByVisits;
			# say "central                  :";
			# p%centralPCRsByVisits;
			# say "symptoms                 :";
			# p%symptomsByVisit;
			# say "limitDate                : $limitDate";
			# say "doeBNT162b2              : $doeBNT162b2";
			# say "doePlacebo               : $doePlacebo";
			# say "doePlaceboToBNT162b2     : $doePlaceboToBNT162b2";

			# Once done with all the required filterings, incrementing stats.
			# Population stats.
			# Total Subjects
			$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjects'}++;
			# Subject's Arm.
			$stats{'Doses Without Infection'}->{$ageGroup}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
			if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
				$stats{'Doses Without Infection'}->{$ageGroup}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
			}
			# Days of exposure for each arm.
			$stats{'Doses Without Infection'}->{$ageGroup}->{'doePlaceboToBNT162b2'} += $doePlaceboToBNT162b2;
			$stats{'Doses Without Infection'}->{$ageGroup}->{'doeBNT162b2'}          += $doeBNT162b2;
			$stats{'Doses Without Infection'}->{$ageGroup}->{'doePlacebo'}           += $doePlacebo;

			# AE stats.
			my ($hasAE, $hasSAE) = (0, 0);
			if (exists $adaes{$subjectId}) {
				# For each date on which AEs have been reported
				for my $aeCompdate (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
					my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
					die unless ($aeY && $aeM && $aeD);
					# Skipping AE if observed after cut-off.
					next if $aeCompdate > $treatmentCutoffCompdate;
					my %doseDatesByDates = ();
					for my $dNum (sort{$a <=> $b} keys %doseDates) {
						my $dt = $doseDates{$dNum} // die;
						my ($cpDt) = split ' ', $dNum;
						$cpDt =~ s/\D//g;
						next unless $cpDt < $aeCompdate;
						my $daysBetween = time::calculate_days_difference("$aeY-$aeM-$aeD 12:00:00", $dt);
						$doseDatesByDates{$daysBetween}->{'closestDoseDate'} = $dt;
						$doseDatesByDates{$daysBetween}->{'closestDose'} = $dNum;
					}
					my ($closestDoseDate, $closestDose, $doseToAEDays);
					for my $daysBetween (sort{$a <=> $b} keys %doseDatesByDates) {
						$closestDoseDate = $doseDatesByDates{$daysBetween}->{'closestDoseDate'} // die;
						$closestDose     = $doseDatesByDates{$daysBetween}->{'closestDose'} // die;
						$doseToAEDays    = $daysBetween;
						last;
					}
					my ($closestDoseCompdate) = split ' ', $closestDoseDate;
					$closestDoseCompdate =~ s/\D//g;
					my $doseArm = $arm;
					if ($arm ne 'Placebo') {
						$doseArm = 'BNT162b2 (30 mcg)';
					}
					if ($closestDose > 2) {
						$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
					}
					# say "*" x 50;
					# say "aeCompdate               : $aeCompdate";
					# say "closestDoseDate          : $closestDoseDate";
					# say "closestDose              : $closestDose";
					# say "doseToAEDays             : $doseToAEDays";
					# say "doseArm                  : $doseArm";

					# For Each adverse effect reported on this date.
					for my $aeObserved (sort keys %{$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}}) {
						# p$adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved};die;
						my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlgt'}        // die;
						# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
						my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aehlt'}         // die;
						my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'aeser'}         // die;
						my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$aeCompdate}->{$aeObserved}->{'toxicityGrade'} || 'NA';
						if ($aeser eq 'Y') {
							$aeser  = 1;
							$hasSAE = 1;
						} elsif ($aeser eq 'N') {
							$aeser = 0;
						} else {
							$aeser = 0;
						}
						$hasAE = 1;
						# say "*" x 50;
						# say "aehlgt                   : $aehlgt";
						# say "aehlt                    : $aehlt";
						# say "aeser                    : $aeser";
						# say "toxicityGrade            : $toxicityGrade";
						# die;

						# Grade level - global stat & by toxicity stats.
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
						if ($aeser) {
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
						}

						# Category level - stats & by toxicity stats
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
						if ($aeser) {
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
						}

						# Reaction level - stats & by toxicity stats. 
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
							$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjects'}++;
						}
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalAEs'}++;
						$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
						if ($aeser) {
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSAEs'}++;
							$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
							unless (exists $subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
								$subjectsAEs{'Doses Without Infection'}->{$ageGroup}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
								$stats{'Doses Without Infection'}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$doseArm}->{'totalSubjectsWithSAEs'}++;
							}
						}
					}
				}
			}
			# Total subjects with AE.
			if ($hasAE) {
				$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjectsWithAE'}++;
			}
			# Total subjects with SAE.
			if ($hasSAE) {
				$stats{'Doses Without Infection'}->{$ageGroup}->{'totalSubjectsWithSAEs'}++;
			}
		}
	}

	# Flushing subjects cache.
	%subjectsAEs = ();
}
say "";
# p$stats{'full_data'};
# die;
# p%stats;
# p%genStats;
# die;

# sub age_to_age_group {
# 	my $age = shift;
# 	my $ageGroup;
# 	if ($age > 5 && $age <= 14) {
# 		$ageGroup = '5-14';
# 	} elsif ($age >= 15 && $age <= 24) {
# 		$ageGroup = '15-24';
# 	} elsif ($age >= 25 && $age <= 34) {
# 		$ageGroup = '25-34';
# 	} elsif ($age >= 35 && $age <= 44) {
# 		$ageGroup = '35-44';
# 	} elsif ($age >= 45 && $age <= 54) {
# 		$ageGroup = '45-54';
# 	} elsif ($age >= 55 && $age <= 64) {
# 		$ageGroup = '55-64';
# 	} elsif ($age >= 65 && $age <= 74) {
# 		$ageGroup = '65-74';
# 	} elsif ($age >= 75 && $age <= 84) {
# 		$ageGroup = '75-84';
# 	} elsif ($age >= 85 && $age <= 94) {
# 		$ageGroup = '85-94';
# 	} else {
# 		die "age : $age";
# 	}
# 	return $ageGroup;
# }

for my $label (sort keys %stats) {
	for my $ageGroup (sort keys %{$stats{$label}}) {
		# p$stats{$label}->{$ageGroup};
		# say "label    : $label";
		# say "ageGroup : $ageGroup";
		my $totalSubjects                = $stats{$label}->{$ageGroup}->{'totalSubjects'}         // next;
		my $totalSubjectsBNT162b2        = $stats{$label}->{$ageGroup}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // die;
		my $totalSubjectsPlacebo         = $stats{$label}->{$ageGroup}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                      // die;
		my $totalSubjectsPlaceboBNT      = $stats{$label}->{$ageGroup}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
		my $totalSubjectsWithAE          = $stats{$label}->{$ageGroup}->{'totalSubjectsWithAE'}   // next;
		my $totalSubjectsWithSAEs        = $stats{$label}->{$ageGroup}->{'totalSubjectsWithSAEs'} // 0;
		my $doePlaceboToBNT162b2         = $stats{$label}->{$ageGroup}->{'doePlaceboToBNT162b2'}  // 0;
		my $doeBNT162b2                  = $stats{$label}->{$ageGroup}->{'doeBNT162b2'}           // die;
		my $doePlacebo                   = $stats{$label}->{$ageGroup}->{'doePlacebo'}            // die;
		my $doeGlobal                    = $doePlaceboToBNT162b2 + $doePlacebo + $doeBNT162b2;
		my $personYearsPlaceboBNT        = nearest(0.01, $doePlaceboToBNT162b2 / 365);
		my $personYearsBNT162b2          = nearest(0.01, $doeBNT162b2          / 365);
		my $personYearsPlacebo           = nearest(0.01, $doePlacebo           / 365);
		my $personYearsGlobal            = nearest(0.01, $doeGlobal            / 365);
		# say "label                  : $label";
		# say "ageGroup                 : $ageGroup";
		# say "label                  : $label";
		# say "totalSubjects              : $totalSubjects";
		# say "totalSubjectsWithSAEs       : $totalSubjectsWithSAEs";
		# say "doeGlobal                  : $doeGlobal";
		# say "doeBNT162b2                : $doeBNT162b2";
		# say "doePlacebo                 : $doePlacebo";
		# say "doePlaceboToBNT162b2       : $doePlaceboToBNT162b2";
		# say "totalSubjectsWithAE        : $totalSubjectsWithAE";
		# say "personYearsGlobal          : $personYearsGlobal";
		# say "personYearsBNT162b2        : $personYearsBNT162b2";
		# say "personYearsPlacebo         : $personYearsPlacebo";
		# say "personYearsPlaceboBNT      : $personYearsPlaceboBNT";
		for my $toxicityGrade (sort keys %{$stats{$label}->{$ageGroup}->{'gradeStats'}}) {
			if (!$toxicityGradeDetails) {
				next unless $toxicityGrade eq 'All Grades';
			}
			# p$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade};
			# say "toxicityGrade              : $toxicityGrade";
			# p$stats{$label};
			say "Printing [adverse_effects/$label/$ageGroup" . "_$toxicityGrade.csv]";
			make_path("adverse_effects/$label") unless (-d "adverse_effects/$label");
			open my $out, '>:utf8', "adverse_effects/$label/$ageGroup" . " - $toxicityGrade.csv";
			print $out "System Organ Class / Preferred Term$csvSeparator$csvSeparator".
					 "Total - N=$totalSubjects | PY=$personYearsGlobal$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
					 "BNT162b2 (30 mcg) - N=$totalSubjectsBNT162b2 | PY=$personYearsBNT162b2$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
					 "Placebo - N=$totalSubjectsPlacebo | PY=$personYearsPlacebo$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator";
			if ($personYearsPlaceboBNT) {
				print $out "Placebo -> BNT162b2 (30 mcg) - N=$totalSubjectsPlaceboBNT | PY=$personYearsPlaceboBNT$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator";
			}
			say $out "";
			print $out "$csvSeparator$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator";
			if ($personYearsPlaceboBNT) {
				print $out "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
					       "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator";
			}
			say $out "";
			my $gradeTotalSubjectsAE           = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}         // 0;
			my $gradeTotalSubjectsSAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'} // 0;
			my $totalAEs                       = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'} // 0;
			my $totalSAEs                      = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'} // 0;
			my $aesBNT162b2                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
			my $placeboAEs                     = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
			my $placeboBNTAEs                  = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalAEs'} // 0;
			my $saesBNT162b2                   = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
			my $placeboSAEs                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
			my $placeboBNTSAEs                 = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSAEs'} // 0;
			my $bNT162b2SubjectsAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
			my $bNT162b2SubjectsSAE            = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
			my $placeboSubjectsAE              = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
			my $placeboSubjectsSAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
			my $placeboBNTSubjectsAE           = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
			my $placeboBNTSubjectsSAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'} // 0;
			my $rateTotalAEsPer100K            = nearest(0.01, $gradeTotalSubjectsAE * 100000 / $personYearsGlobal);
			my $rateTotalSAEsPer100K           = nearest(0.01, $gradeTotalSubjectsSAE * 100000 / $personYearsGlobal);
			my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE * 100000 / $personYearsBNT162b2);
			my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE * 100000 / $personYearsBNT162b2);
			my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE * 100000 / $personYearsPlacebo);
			my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE * 100000 / $personYearsPlacebo);
			my $totalPercentOfTotalAEs         = nearest(0.01, $gradeTotalSubjectsAE * 100 / $totalSubjects);
			my $totalPercentOfTotalSAEs        = nearest(0.01, $gradeTotalSubjectsSAE * 100 / $totalSubjects);
			my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE   * 100 / $totalSubjectsBNT162b2);
			my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE  * 100 / $totalSubjectsBNT162b2);
			my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE    * 100 / $totalSubjectsPlacebo);
			my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100 / $totalSubjectsPlacebo);
			# say "totalAEs                   : $totalAEs";
			# say "gradeTotalSubjectsAE       : $gradeTotalSubjectsAE";
			# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
			# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
			# say "totalSAEs                  : $totalSAEs";
			# say "gradeTotalSubjectsSAE      : $gradeTotalSubjectsSAE";
			# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
			print $out "All$csvSeparator" . "All$csvSeparator" .
					   "$totalAEs$csvSeparator$gradeTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
					   "$totalSAEs$csvSeparator$gradeTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
					   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
					   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
					   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
					   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
			if ($personYearsPlaceboBNT) {
				my $placeboBNTPercentOfTotalAE     = 0;
				my $placeboBNTPercentOfTotalSAE    = 0;
				if ($totalSubjectsPlaceboBNT) {
					$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsPlaceboBNT);
					$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsPlaceboBNT);
				}
				my $ratePlaceboBNTSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsPlaceboBNT);
				my $ratePlaceboBNTAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsPlaceboBNT);
				print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$ratePlaceboBNTAEsPer100K$csvSeparator" .
				           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$ratePlaceboBNTSAEsPer100K$csvSeparator";
			}
			say $out "";
			for my $aehlgt (sort keys %{$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}}) {
				my $aehlgtTotalSubjectsAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}         // 0;
				my $aehlgtTotalSubjectsSAE         = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'} // 0;
				my $totalAEs                       = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'} // 0;
				my $totalSAEs                      = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'} // 0;
				my $aesBNT162b2                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
				my $placeboAEs                     = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
				my $placeboBNTAEs                  = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalAEs'} // 0;
				my $saesBNT162b2                   = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
				my $placeboSAEs                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
				my $placeboBNTSAEs                 = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSAEs'} // 0;
				my $bNT162b2SubjectsAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
				my $bNT162b2SubjectsSAE            = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
				my $placeboSubjectsAE              = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
				my $placeboSubjectsSAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
				my $placeboBNTSubjectsAE           = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
				my $placeboBNTSubjectsSAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'} // 0;
				my $rateTotalAEsPer100K            = nearest(0.01, $aehlgtTotalSubjectsAE * 100000 / $personYearsGlobal);
				my $rateTotalSAEsPer100K           = nearest(0.01, $aehlgtTotalSubjectsSAE * 100000 / $personYearsGlobal);
				my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE * 100000 / $personYearsBNT162b2);
				my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE * 100000 / $personYearsBNT162b2);
				my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE * 100000 / $personYearsPlacebo);
				my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE * 100000 / $personYearsPlacebo);
				my $totalPercentOfTotalAEs         = nearest(0.01, $aehlgtTotalSubjectsAE * 100 / $totalSubjects);
				my $totalPercentOfTotalSAEs        = nearest(0.01, $aehlgtTotalSubjectsSAE * 100 / $totalSubjects);
				my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE   * 100 / $totalSubjectsBNT162b2);
				my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE  * 100 / $totalSubjectsBNT162b2);
				my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE    * 100 / $totalSubjectsPlacebo);
				my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100 / $totalSubjectsPlacebo);
				# say "totalAEs                   : $totalAEs";
				# say "gradeTotalSubjectsAE       : $aehlgtTotalSubjectsAE";
				# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
				# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
				# say "totalSAEs                  : $totalSAEs";
				# say "gradeTotalSubjectsSAE      : $aehlgtTotalSubjectsSAE";
				# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
				print $out "$aehlgt$csvSeparator" . "All$csvSeparator" .
						   "$totalAEs$csvSeparator$aehlgtTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
						   "$totalSAEs$csvSeparator$aehlgtTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
						   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
						   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
						   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
						   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
				if ($personYearsPlaceboBNT) {
					my $placeboBNTPercentOfTotalAE     = 0;
					my $placeboBNTPercentOfTotalSAE    = 0;
					if ($totalSubjectsPlaceboBNT) {
						$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsPlaceboBNT);
						$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsPlaceboBNT);
					}
					my $ratePlaceboBNTSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsPlaceboBNT);
					my $ratePlaceboBNTAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsPlaceboBNT);
					print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$ratePlaceboBNTAEsPer100K$csvSeparator" .
					           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$ratePlaceboBNTSAEsPer100K$csvSeparator";
				}
				say $out "";
				for my $aehlt (sort keys %{$stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}}) {
					my $aehltTotalSubjectsAE           = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}         // 0;
					my $aehltTotalSubjectsSAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'} // 0;
					my $totalAEs                       = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'} // 0;
					my $totalSAEs                      = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'} // 0;
					my $aesBNT162b2                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
					my $placeboAEs                     = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
					my $placeboBNTAEs                  = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalAEs'} // 0;
					my $saesBNT162b2                   = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
					my $placeboSAEs                    = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
					my $placeboBNTSAEs                 = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSAEs'} // 0;
					my $bNT162b2SubjectsAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
					my $bNT162b2SubjectsSAE            = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
					my $placeboSubjectsAE              = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
					my $placeboSubjectsSAE             = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
					my $placeboBNTSubjectsAE           = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
					my $placeboBNTSubjectsSAE          = $stats{$label}->{$ageGroup}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'} // 0;
					my $rateTotalAEsPer100K            = nearest(0.01, $aehltTotalSubjectsAE * 100000 / $personYearsGlobal);
					my $rateTotalSAEsPer100K           = nearest(0.01, $aehltTotalSubjectsSAE * 100000 / $personYearsGlobal);
					my $rateBNT162b2SAEsPer100K        = nearest(0.01, $bNT162b2SubjectsSAE * 100000 / $personYearsBNT162b2);
					my $rateBNT162b2AEsPer100K         = nearest(0.01, $bNT162b2SubjectsAE * 100000 / $personYearsBNT162b2);
					my $ratePlaceboSAEsPer100K         = nearest(0.01, $placeboSubjectsSAE * 100000 / $personYearsPlacebo);
					my $ratePlaceboAEsPer100K          = nearest(0.01, $placeboSubjectsAE * 100000 / $personYearsPlacebo);
					my $totalPercentOfTotalAEs         = nearest(0.01, $aehltTotalSubjectsAE * 100 / $totalSubjects);
					my $totalPercentOfTotalSAEs        = nearest(0.01, $aehltTotalSubjectsSAE * 100 / $totalSubjects);
					my $bnt162B2PercentOfTotalAE       = nearest(0.01, $bNT162b2SubjectsAE   * 100 / $totalSubjectsBNT162b2);
					my $bnt162B2PercentOfTotalSAE      = nearest(0.01, $bNT162b2SubjectsSAE  * 100 / $totalSubjectsBNT162b2);
					my $placeboPercentOfTotalAE        = nearest(0.01, $placeboSubjectsAE    * 100 / $totalSubjectsPlacebo);
					my $placeboPercentOfTotalSAE       = nearest(0.01, $placeboSubjectsSAE    * 100 / $totalSubjectsPlacebo);
					# say "totalAEs                   : $totalAEs";
					# say "gradeTotalSubjectsAE       : $aehlgtTotalSubjectsAE";
					# say "totalPercentOfTotalAEs     : $totalPercentOfTotalAEs";
					# say "rateTotalAEsPer100K        : $rateTotalAEsPer100K";
					# say "totalSAEs                  : $totalSAEs";
					# say "gradeTotalSubjectsSAE      : $aehlgtTotalSubjectsSAE";
					# say "totalPercentOfTotalSAEs    : $totalPercentOfTotalSAEs";
					print $out "$csvSeparator$aehlt$csvSeparator" .
							   "$totalAEs$csvSeparator$aehltTotalSubjectsAE$csvSeparator$totalPercentOfTotalAEs$csvSeparator$rateTotalAEsPer100K$csvSeparator" .
							   "$totalSAEs$csvSeparator$aehltTotalSubjectsSAE$csvSeparator$totalPercentOfTotalSAEs$csvSeparator$rateTotalSAEsPer100K$csvSeparator" .
							   "$aesBNT162b2$csvSeparator$bNT162b2SubjectsAE$csvSeparator$bnt162B2PercentOfTotalAE$csvSeparator$rateBNT162b2AEsPer100K$csvSeparator" .
							   "$saesBNT162b2$csvSeparator$bNT162b2SubjectsSAE$csvSeparator$bnt162B2PercentOfTotalSAE$csvSeparator$rateBNT162b2SAEsPer100K$csvSeparator" .
							   "$placeboAEs$csvSeparator$placeboSubjectsAE$csvSeparator$placeboPercentOfTotalAE$csvSeparator$ratePlaceboAEsPer100K$csvSeparator" .
							   "$placeboSAEs$csvSeparator$placeboSubjectsSAE$csvSeparator$placeboPercentOfTotalSAE$csvSeparator$ratePlaceboSAEsPer100K$csvSeparator";
					if ($personYearsPlaceboBNT) {
						my $placeboBNTPercentOfTotalAE     = 0;
						my $placeboBNTPercentOfTotalSAE    = 0;
						if ($totalSubjectsPlaceboBNT) {
							$placeboBNTPercentOfTotalAE    = nearest(0.01, $placeboBNTSubjectsAE * 100 / $totalSubjectsPlaceboBNT);
							$placeboBNTPercentOfTotalSAE   = nearest(0.01, $placeboBNTSubjectsSAE * 100 / $totalSubjectsPlaceboBNT);
						}
						my $ratePlaceboBNTSAEsPer100K         = nearest(0.01, $placeboBNTSubjectsSAE * 100000 / $personYearsPlaceboBNT);
						my $ratePlaceboBNTAEsPer100K          = nearest(0.01, $placeboBNTSubjectsAE * 100000 / $personYearsPlaceboBNT);
						print $out "$placeboBNTAEs$csvSeparator$placeboBNTSubjectsAE$csvSeparator$placeboBNTPercentOfTotalAE$csvSeparator$ratePlaceboBNTAEsPer100K$csvSeparator" .
						           "$placeboBNTSAEs$csvSeparator$placeboBNTSubjectsSAE$csvSeparator$placeboBNTPercentOfTotalSAE$csvSeparator$ratePlaceboBNTSAEsPer100K$csvSeparator";
					}
					say $out "";
			# 		say $out ";$aehlt;$aesBNT162b2;$saesBNT162b2;$bNT162b2Subjects;$bnt162B2PercentOfTotal;$placeboAEs;$placeboSAEs;$placeboSubjectsAE;$placeboPercentOfTotalAE;$placeboBNTAEs;$placeboBNTSAEs;$placeboBNTSubjectsAE;$placeboBNTPercentOfTotalAE;$aehltTotalAEs;$aehltTotalSAEs;$aehltTotalSubjects;$totalPercentOfTotalAEs;";
				}
			}
			close $out;
		}
	}
}

sub age_to_age_group {
	my $age = shift;
	my $ageGroup;
	if ($age > 5 && $age < 16) {
		die "wut";
	} elsif ($age >= 16 && $age <= 54) {
		$ageGroup = '16-54';
	} elsif ($age >= 55 && $age <= 94) {
		$ageGroup = '55+';
	} else {
		die "age : $age";
	}
	return $ageGroup;
}

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

sub load_adva {
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

sub load_adae {
	open my $in, '<:utf8', $adaeFile or die "Missing file [$adaeFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%adaes = %$json;
	say "[$adaeFile] -> subjects : " . keys %adaes;
}

sub load_pcr_tests {
	open my $in, '<:utf8', $pcrRecordsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pcrRecords = %$json;
	# p$pcrRecords{'44441222'};
	say "[$pcrRecordsFile] -> subjects : " . keys %pcrRecords;
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

sub load_faces {
	open my $in, '<:utf8', $faceFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%faces = %$json;
	# p%faces;die;
	say "[$faceFile] -> subjects : " . keys %faces;
}

sub load_tests_refs {
	open my $in, '<:utf8', $testsRefsFile or die "Missing file [$testsRefsFile]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%testsRefs = %$json;
	say "[$testsRefsFile] -> tests    : " . keys %testsRefs;
}

sub subject_central_pcrs_by_visits {
	my ($subjectId) = @_;
	my %centralPCRsByVisits    = ();
	my $hasPositiveCentralPCR = 0;
	for my $visitDate (sort keys %{$pcrRecords{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= $cutoffCompdate;
		my $pcrResult = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		my $visitName = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		if (exists $centralPCRsByVisits{$visitName}->{'pcrResult'} && ($centralPCRsByVisits{$visitName}->{'pcrResult'} ne $pcrResult)) {
			next unless $pcrResult eq 'POS'; # If several conflicting tests on the same date, we only sustain the last positive one.
		}
		$centralPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$centralPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$centralPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		if ($pcrResult eq 'POS') {
			$hasPositiveCentralPCR = 1;
		} elsif ($pcrResult eq 'NEG') {
		} elsif ($pcrResult eq 'IND' || $pcrResult eq '') {
			$genStats{'missingPCRResults'}->{$pcrResult}++;
		} else {
			die "pcrResult : $pcrResult";
		}
	}
	return (
		$hasPositiveCentralPCR,
		%centralPCRsByVisits);
}

sub subject_local_pcrs_by_visits {
	my ($subjectId)  = @_;
	my %localPCRsByVisits   = ();
	my $hasPositiveLocalPCR = 0;
	for my $visitDate (sort keys %{$pcrRecords{$subjectId}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'};
		my $visitCompdate = $visitDate;
		$visitCompdate =~ s/\D//g;

		# Skips the visit unless it fits with the phase 3.
		next unless $visitCompdate >= 20200720;
		next unless $visitCompdate <= $cutoffCompdate;
		my $pcrResult = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'mbResult'} // die;
		my $visitName = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		my $spDevId   = $pcrRecords{$subjectId}->{'mbVisits'}->{$visitDate}->{'SEVERE ACUTE RESP SYNDROME CORONAVIRUS 2'}->{'spDevId'}  // die;
		if ($spDevId) {
			die "spDevId: $spDevId" unless $spDevId && looks_like_number $spDevId;
			die unless exists $testsRefs{$spDevId};
			my $deviceType = $testsRefs{$spDevId}->{'Device Type'} // die;
			my $tradeName  = $testsRefs{$spDevId}->{'Trade Name'}  // die;
			$spDevId = "$deviceType - $tradeName ($spDevId)";
		} else {
			$spDevId = 'Not Provided';
		}
		if ($pcrResult eq 'POSITIVE') {
			$pcrResult = 'POS';
		} elsif ($pcrResult eq 'NEGATIVE') {
			$pcrResult = 'NEG';
		} elsif ($pcrResult eq 'INDETERMINATE' || $pcrResult eq '') {
			$pcrResult = 'IND';
		} else {
			die "pcrResult : $pcrResult";
		}
		next if exists $localPCRsByVisits{$visitName}->{'pcrResult'} && ($localPCRsByVisits{$visitName}->{'pcrResult'} ne $pcrResult && $pcrResult ne 'POS');
		$localPCRsByVisits{$visitName}->{'visitDate'}     = $visitDate;
		$localPCRsByVisits{$visitName}->{'pcrResult'}     = $pcrResult;
		$localPCRsByVisits{$visitName}->{'visitCompdate'} = $visitCompdate;
		$localPCRsByVisits{$visitName}->{'spDevId'}       = $spDevId;
		if ($pcrResult eq 'POS') {
			$hasPositiveLocalPCR = 1;
		}
	}

	return ($hasPositiveLocalPCR,
		%localPCRsByVisits);
}

sub subject_symptoms_by_visits {
	my ($subjectId) = @_;
	my %symptomsByVisits = ();
	my $hasSymptoms      = 0;
	for my $symptomDatetime (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}}) {
		my ($symptomDate)   = split ' ', $symptomDatetime;
		my $compsympt = $symptomDate;
		$compsympt =~ s/\D//g;

		# Comment these lines to stick with the visit date.
		my ($formerSymptomDate, $onsetStartOffset);
		if (exists $faces{$subjectId}->{$symptomDate}) {
			my $altStartDate = $faces{$subjectId}->{$symptomDate}->{'symptomsDates'}->{'First Symptom Date'} // die;
			unless ($altStartDate eq $symptomDate) {
				if ($altStartDate =~ /^....-..-..$/) {
					my $compalt = $altStartDate;
					$compalt =~ s/\D//g;
					if ($compalt < $compsympt) {
						$formerSymptomDate = $symptomDate;
						$onsetStartOffset  = time::calculate_days_difference("$symptomDate 12:00:00", "$altStartDate 12:00:00");
						$symptomDate = $altStartDate;
					}
				}
			}
		}
		my $symptomCompdate = $symptomDate;
		$symptomCompdate    =~ s/\D//g;
		next unless $symptomCompdate <= $cutoffCompdate;
		my $totalSymptoms   = 0;
		my $hasOfficialSymptoms = 0;
		my $endDatetime = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'endDatetime'};
		my $visitName = $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'visitName'} // die;
		for my $symptomName (sort keys %{$symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}}) {
			next unless $symptoms{$subjectId}->{'symptomsReports'}->{$symptomDatetime}->{'symptoms'}->{$symptomName} eq 'Y';
			my $symptomCategory = symptom_category_from_symptom($symptomName);
			if ($officialSymptomsOnly) {
				next unless $symptomCategory eq 'OFFICIAL';
			}
			$hasOfficialSymptoms = 1 if $symptomCategory eq 'OFFICIAL';
			$symptomsByVisits{$visitName}->{'symptoms'}->{$symptomName} = 1;
			$totalSymptoms++;
		}
		next unless $totalSymptoms;
		$hasSymptoms  = 1;
		$symptomsByVisits{$visitName}->{'onsetStartOffset'}    = $onsetStartOffset;
		$symptomsByVisits{$visitName}->{'formerSymptomDate'}   = $formerSymptomDate;
		$symptomsByVisits{$visitName}->{'symptomCompdate'}     = $symptomCompdate;
		$symptomsByVisits{$visitName}->{'symptomDate'}         = $symptomDate;
		$symptomsByVisits{$visitName}->{'totalSymptoms'}       = $totalSymptoms;
		$symptomsByVisits{$visitName}->{'endDatetime'}         = $endDatetime;
		$symptomsByVisits{$visitName}->{'hasOfficialSymptoms'} = $hasOfficialSymptoms;
	}
	return (
		$hasSymptoms,
		%symptomsByVisits);
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

sub time_of_exposure_from_simple {
	my ($arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose1Date, $dose2Date, $dose3Date, $deathDatetime, $deathCompdate) = @_;
	my ($doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2) = (0, 0, 0);
	my $groupArm = $arm;
	if ($arm ne 'Placebo') {
		$groupArm = 'BNT162b2 (30 mcg)';
	}
	my $treatmentCutoffCompdate = $cutoffCompdate;
	if ($dose3Datetime) {
		die unless $arm eq 'Placebo';
		$groupArm = 'Placebo -> BNT162b2 (30 mcg)';
		$doePlacebo = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
		if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
			$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $deathDatetime);
		} else {
			$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $cutoffDatetime);
		}
	} else {
		my $daysBetweenDoseAndCutOff;
		if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
			$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
		} else {
			$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $cutoffDatetime);
		}
		if ($arm eq 'Placebo') {
			$doePlacebo  += $daysBetweenDoseAndCutOff;
		} else {
			$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
		}
	}
	return ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate);
}

sub time_of_exposure_from_conflicting {
	my ($label, $arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose4Datetime, $dose1Date, $dose2Date, $dose3Date, $dose4Date, $deathDatetime, $deathCompdate, $lastDosePriorCovidDatetime, $lastDosePriorCovidDate, $lastDosePriorCovid, $earliestCovid) = @_;
	# say "$label, $arm, $dose1Datetime, $dose2Datetime, $dose3Datetime, $dose4Datetime, $dose1Date, $dose2Date, $dose3Date, $dose4Date, $deathDatetime, $deathCompdate, $lastDosePriorCovidDatetime, $lastDosePriorCovidDate, $lastDosePriorCovid, $earliestCovid";
	# die;
	my ($doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2) = (0, 0, 0);
	my $groupArm = $arm;
	my $treatmentCutoffCompdate = $cutoffCompdate;
	if ($arm ne 'Placebo') {
		$groupArm = 'BNT162b2 (30 mcg)';
	}
	if ($lastDosePriorCovid == 1) {
		# If label eq 'Prior Exposure', Time is accrued up to dose 2. Else, time is accrued from dose 2 to end (death or cutoff).
		if ($label eq 'Doses Without Infection' && ($dose2Datetime || $dose3Datetime)) {
			my $daysBetweenDoseAndCutOff;
			if ($dose2Datetime) {
				if ($deathDatetime && ($deathCompdate < $dose2Date)) {
					$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
				} else {
					$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $dose2Datetime);
				}
			} else {
				if ($dose3Datetime) {
					if ($deathDatetime && ($deathCompdate < $dose3Date)) {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
					} else {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
					}
				} else {
					if ($deathDatetime && ($deathCompdate < $treatmentCutoffCompdate)) {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
					} else {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
					}
				}
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && ($dose2Datetime || $dose3Datetime)) {
			if ($dose3Datetime) {
				die unless $arm eq 'Placebo';
				$groupArm = 'Placebo -> BNT162b2 (30 mcg)';
				$doePlacebo = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
				if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
					$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $deathDatetime);
				} else {
					$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $cutoffDatetime);
				}
			} else {
				my $daysBetweenDoseAndCutOff;
				if ($dose2Datetime) {
					if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose2Datetime, $deathDatetime);
					} else {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose2Datetime, $cutoffDatetime);
					}
				} else {
					if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose3Datetime, $deathDatetime);
					} else {
						$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose3Datetime, $cutoffDatetime);
					}
				}
				if ($arm eq 'Placebo') {
					$doePlacebo  += $daysBetweenDoseAndCutOff;
				} else {
					$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
				}
			}
		} elsif ($label eq 'Doses Without Infection' && (!$dose2Datetime && !$dose3Datetime)) {
			my $daysBetweenDoseAndCutOff;
			if ($deathDatetime && ($deathCompdate < $treatmentCutoffCompdate)) {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
			} else {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $cutoffDatetime);
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && (!$dose2Datetime && !$dose3Datetime)) {

		} else {
			die "label : [$label]";
		}
	} elsif ($lastDosePriorCovid == 2) {
		# If label eq 'Prior Exposure', Time is accrued up to dose 3. Else, time is accrued from dose 3 to end (death or cutoff).
		if ($label eq 'Doses Without Infection' && $dose3Datetime) {
			my $daysBetweenDoseAndCutOff;
			if ($deathDatetime && ($deathCompdate < $dose3Date)) {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
			} else {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && $dose3Datetime) {
			die unless $arm eq 'Placebo';
			$groupArm = 'Placebo -> BNT162b2 (30 mcg)';
			$doePlacebo = time::calculate_days_difference($dose1Datetime, $dose3Datetime);
			if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
				$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $deathDatetime);
			} else {
				$doePlaceboToBNT162b2 = time::calculate_days_difference($dose3Datetime, $cutoffDatetime);
			}
		} elsif ($label eq 'Doses Without Infection' && !$dose3Datetime) {
			my $daysBetweenDoseAndCutOff;
			if ($deathDatetime && ($deathCompdate < $treatmentCutoffCompdate)) {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
			} else {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $cutoffDatetime);
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && !$dose3Datetime) {
			
		} else {
			die "label : [$label]";
		}
	} elsif ($lastDosePriorCovid == 3) {
		# If label eq 'Prior Exposure', Time is accrued up to dose 4. Else, time is accrued from dose 4 to end (death or cutoff).
		if ($label eq 'Doses Without Infection' && $dose4Datetime) {
			my $daysBetweenDoseAndCutOff;
			if ($deathDatetime && ($deathCompdate < $dose3Date)) {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
			} else {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $dose4Datetime);
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && $dose4Datetime) {
			die unless $arm eq 'Placebo';
			$groupArm = 'Placebo -> BNT162b2 (30 mcg)';
			$doePlacebo = time::calculate_days_difference($dose1Datetime, $dose4Datetime);
			if ($deathDatetime && ($deathCompdate < $cutoffCompdate)) {
				$doePlaceboToBNT162b2 = time::calculate_days_difference($dose4Datetime, $deathDatetime);
			} else {
				$doePlaceboToBNT162b2 = time::calculate_days_difference($dose4Datetime, $cutoffDatetime);
			}
		} elsif ($label eq 'Doses Without Infection' && !$dose4Datetime) {
			my $daysBetweenDoseAndCutOff;
			if ($deathDatetime && ($deathCompdate < $treatmentCutoffCompdate)) {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
			} else {
				$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $cutoffDatetime);
			}
			if ($arm eq 'Placebo') {
				$doePlacebo  += $daysBetweenDoseAndCutOff;
			} else {
				$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
			}
		} elsif ($label eq 'Doses Post Infection' && !$dose4Datetime) {
			
		} else {
			die "label : [$label]";
		}
	} elsif ($lastDosePriorCovid == 4) {
		die;
	} else {
		die;
	}
	return ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2, $treatmentCutoffCompdate);
}