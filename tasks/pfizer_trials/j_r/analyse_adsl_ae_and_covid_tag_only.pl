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
use lib "$FindBin::Bin/../../../lib";
use time;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use time;

# Treatment configuration.
my $toxicityGradeDetails = 0;   # Either 0 or 1 (1 = with grade details).
my $csvSeparator         = ';'; # Whichever char is best for your OS localization.
my $cutoffCompdate       = '20210313';
my ($cY, $cM, $cD)       = $cutoffCompdate =~ /(....)(..)(..)/;
my $cutoffDatetime       = "$cY-$cM-$cD 12:00:00";

# Loading data required.
my $adslFile             = 'public/doc/pfizer_trials/pfizer_adsl_patients.json';
my $adaeFile             = 'public/doc/pfizer_trials/pfizer_adae_patients.json';
my $advaFile             = "public/doc/pfizer_trials/pfizer_adva_patients.json";

my %adsl                 = ();
my %adaes                = ();
my %advaData             = ();
load_adsl();
load_adae();
load_adva();

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
	my $unblindingDatetime = $adsl{$subjectId}->{'unblindingDatetime'} || $cutoffDatetime;
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
	if ($arm ne 'Placebo') {
		$arm = 'BNT162b2 (30 mcg)';
	}
	my $randomizationDatetime = $adsl{$subjectId}->{'randomizationDatetime'} // '';
	my $randomizationDate     = $adsl{$subjectId}->{'randomizationDate'};
	my $dose2Date             = $adsl{$subjectId}->{'dose2Date'};
	my $dose2Datetime         = $adsl{$subjectId}->{'dose2Datetime'};
	my $dose3Date             = $adsl{$subjectId}->{'dose3Date'};
	my $dose3Datetime         = $adsl{$subjectId}->{'dose3Datetime'};
	if ($dose3Datetime) {
		die unless $unblindingDatetime;
	}
	my $dose4Date             = $adsl{$subjectId}->{'dose4Date'};
	my $dose4Datetime         = $adsl{$subjectId}->{'dose4Datetime'};
	my $covidAtBaseline       = $adsl{$subjectId}->{'covidAtBaseline'}       // die;

	# Setting Covid at baseline own tags.
	my ($covidAtBaselineRecalc, $covidAtBaselineRecalcSource) = (0, undef);
	if ($covidAtBaseline eq 'POS') {
		$covidAtBaselineRecalc = 1;
		$covidAtBaselineRecalcSource = 'Baseline tag';
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
		my ($groupArm, $doeBNT162b2, $doePlacebo) = time_of_exposure_from_simple($arm, $dose1Datetime, $dose2Datetime, $dose1Date, $dose2Date, $deathDatetime, $deathCompdate, $unblindingDatetime, $unblindingDate);
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
		$stats{'Doses Post Infection'}->{'totalSubjects'}++;
		# Subject's Arm.
		$stats{'Doses Post Infection'}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
		if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
			$stats{'Doses Post Infection'}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
		}
		# Days of exposure for each arm.
		$stats{'Doses Post Infection'}->{'doeBNT162b2'}          += $doeBNT162b2;
		$stats{'Doses Post Infection'}->{'doePlacebo'}           += $doePlacebo;

		# AE stats.
		my ($hasAE, $hasSAE) = (0, 0);
		if (exists $adaes{$subjectId}) {
			# For each date on which AEs have been reported
			for my $drNum (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
				# p$adaes{$subjectId}->{'adverseEffects'}->{$drNum};die;
				my $aeCompdate    = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aeCompdate'};
				if ($aeCompdate) {
					next unless $aeCompdate <= $unblindingDate;
				}
				my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aehlgt'}        // die;
				# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
				my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aehlt'}         // die;
				my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aeser'}         // die;
				my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'toxicityGrade'} || 'NA';
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
				unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}

				# Category level - stats & by toxicity stats
				unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}

				# Reaction level - stats & by toxicity stats. 
				unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Post Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Post Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}
			}
		}
		# Total subjects with AE.
		if ($hasAE) {
			$stats{'Doses Post Infection'}->{'totalSubjectsWithAE'}++;
		}
		# Total subjects with SAE.
		if ($hasSAE) {
			$stats{'Doses Post Infection'}->{'totalSubjectsWithSAEs'}++;
		}
	} else {

		# Setting values related to subject's populations.
		my ($groupArm, $doeBNT162b2, $doePlacebo) = time_of_exposure_from_simple($arm, $dose1Datetime, $dose2Datetime, $dose1Date, $dose2Date, $deathDatetime, $deathCompdate, $unblindingDatetime, $unblindingDate);
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
		$stats{'Doses Without Infection'}->{'totalSubjects'}++;
		# Subject's Arm.
		$stats{'Doses Without Infection'}->{'byArms'}->{$groupArm}->{'totalSubjects'}++;
		if ($groupArm eq 'Placebo -> BNT162b2 (30 mcg)') { # If switched arms, also counts as BNT subject.
			$stats{'Doses Without Infection'}->{'byArms'}->{'Placebo'}->{'totalSubjects'}++;
		}
		# Days of exposure for each arm.
		$stats{'Doses Without Infection'}->{'doeBNT162b2'}          += $doeBNT162b2;
		$stats{'Doses Without Infection'}->{'doePlacebo'}           += $doePlacebo;

		# AE stats.
		my ($hasAE, $hasSAE) = (0, 0);
		if (exists $adaes{$subjectId}) {
			# For each date on which AEs have been reported
			for my $drNum (sort{$a <=> $b} keys %{$adaes{$subjectId}->{'adverseEffects'}}) {
				my $aeCompdate    = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aeCompdate'};
				if ($aeCompdate) {
					next unless $aeCompdate <= $unblindingDate;
				}
				my $aehlgt        = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aehlgt'}        // die;
				# next unless $aehlgt eq 'Pulmonary vascular disorders'; ################### DEBUG.
				my $aehlt         = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aehlt'}         // die;
				my $aeser         = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'aeser'}         // die;
				my $toxicityGrade = $adaes{$subjectId}->{'adverseEffects'}->{$drNum}->{'toxicityGrade'} || 'NA';
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
				unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}

				# Category level - stats & by toxicity stats
				unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}

				# Reaction level - stats & by toxicity stats. 
				unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'}) {
					$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'subject'} = 1;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjects'}++;
				}
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalAEs'}++;
				$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'}++;
				if ($aeser) {
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSAEs'}++;
					$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'}++;
					unless (exists $subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{'All Grades'}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
					unless (exists $subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'}) {
						$subjectsAEs{'Doses Without Infection'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'subjects'}->{$subjectId}->{'SAE'} = 1;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'}++;
						$stats{'Doses Without Infection'}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{$arm}->{'totalSubjectsWithSAEs'}++;
					}
				}
			}
		}
		# Total subjects with AE.
		if ($hasAE) {
			$stats{'Doses Without Infection'}->{'totalSubjectsWithAE'}++;
		}
		# Total subjects with SAE.
		if ($hasSAE) {
			$stats{'Doses Without Infection'}->{'totalSubjectsWithSAEs'}++;
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
	# p$stats{$label};
	# say "label    : $label";
	# say "ageGroup : $ageGroup";
	my $totalSubjects                = $stats{$label}->{'totalSubjects'}         // next;
	my $totalSubjectsBNT162b2        = $stats{$label}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // die;
	my $totalSubjectsPlacebo         = $stats{$label}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                      // die;
	my $totalSubjectsPlaceboBNT      = $stats{$label}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
	my $totalSubjectsWithAE          = $stats{$label}->{'totalSubjectsWithAE'}   // next;
	my $totalSubjectsWithSAEs        = $stats{$label}->{'totalSubjectsWithSAEs'} // 0;
	my $doeBNT162b2                  = $stats{$label}->{'doeBNT162b2'}           // die;
	my $doePlacebo                   = $stats{$label}->{'doePlacebo'}            // die;
	my $doeGlobal                    = $doePlacebo + $doeBNT162b2;
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
	for my $toxicityGrade (sort keys %{$stats{$label}->{'gradeStats'}}) {
		if (!$toxicityGradeDetails) {
			next unless $toxicityGrade eq 'All Grades';
		}
		# p$stats{$label}->{'gradeStats'}->{$toxicityGrade};
		# say "toxicityGrade              : $toxicityGrade";
		# p$stats{$label};
		say "Printing [adverse_effects/$label/$toxicityGrade.csv]";
		make_path("adverse_effects/$label") unless (-d "adverse_effects/$label");
		open my $out, '>:utf8', "adverse_effects/$label/$toxicityGrade.csv";
		print $out "System Organ Class / Preferred Term$csvSeparator$csvSeparator".
				 "Total - N=$totalSubjects | PY=$personYearsGlobal$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
				 "BNT162b2 (30 mcg) - N=$totalSubjectsBNT162b2 | PY=$personYearsBNT162b2$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator" .
				 "Placebo - N=$totalSubjectsPlacebo | PY=$personYearsPlacebo$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator$csvSeparator";
		say $out "";
		print $out "$csvSeparator$csvSeparator" .
				   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
				   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
				   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
				   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
				   "AEs$csvSeparator"  . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator" .
				   "SAEs$csvSeparator" . "Subjects$csvSeparator\%$csvSeparator" . "Per 100K / PY$csvSeparator";
		say $out "";
		my $gradeTotalSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjects'}         // 0;
		my $gradeTotalSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'totalSubjectsWithSAEs'} // 0;
		my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'totalAEs'} // 0;
		my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'totalSAEs'} // 0;
		my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
		my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
		my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
		my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
		my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
		my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
		my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
		my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
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
		say $out "";
		for my $aehlgt (sort keys %{$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}}) {
			my $aehlgtTotalSubjectsAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjects'}         // 0;
			my $aehlgtTotalSubjectsSAE         = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSubjectsWithSAEs'} // 0;
			my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalAEs'} // 0;
			my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'totalSAEs'} // 0;
			my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
			my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
			my $placeboBNTAEs                  = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalAEs'} // 0;
			my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
			my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
			my $placeboBNTSAEs                 = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSAEs'} // 0;
			my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
			my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
			my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
			my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
			my $placeboBNTSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
			my $placeboBNTSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'} // 0;
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
			say $out "";
			for my $aehlt (sort keys %{$stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}}) {
				my $aehltTotalSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjects'}         // 0;
				my $aehltTotalSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSubjectsWithSAEs'} // 0;
				my $totalAEs                       = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalAEs'} // 0;
				my $totalSAEs                      = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'totalSAEs'} // 0;
				my $aesBNT162b2                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalAEs'}            // 0;
				my $placeboAEs                     = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalAEs'}                                // 0;
				my $placeboBNTAEs                  = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalAEs'} // 0;
				my $saesBNT162b2                   = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSAEs'}            // 0;
				my $placeboSAEs                    = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSAEs'}                                // 0;
				my $placeboBNTSAEs                 = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSAEs'} // 0;
				my $bNT162b2SubjectsAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjects'}            // 0;
				my $bNT162b2SubjectsSAE            = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'}            // 0;
				my $placeboSubjectsAE              = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSubjects'}                                // 0;
				my $placeboSubjectsSAE             = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo'}->{'totalSubjectsWithSAEs'}                                // 0;
				my $placeboBNTSubjectsAE           = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjects'} // 0;
				my $placeboBNTSubjectsSAE          = $stats{$label}->{'gradeStats'}->{$toxicityGrade}->{'categories'}->{$aehlgt}->{'reactions'}->{$aehlt}->{'byArms'}->{'Placebo -> BNT162b2 (30 mcg)'}->{'totalSubjectsWithSAEs'} // 0;
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
				say $out "";
		# 		say $out ";$aehlt;$aesBNT162b2;$saesBNT162b2;$bNT162b2Subjects;$bnt162B2PercentOfTotal;$placeboAEs;$placeboSAEs;$placeboSubjectsAE;$placeboPercentOfTotalAE;$placeboBNTAEs;$placeboBNTSAEs;$placeboBNTSubjectsAE;$placeboBNTPercentOfTotalAE;$aehltTotalAEs;$aehltTotalSAEs;$aehltTotalSubjects;$totalPercentOfTotalAEs;";
			}
		}
		close $out;
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

sub time_of_exposure_from_simple {
	my ($arm, $dose1Datetime, $dose2Datetime, $dose1Date, $dose2Date, $deathDatetime, $deathCompdate, $unblindingDatetime, $unblindingDate) = @_;
	my ($doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2) = (0, 0, 0);
	my $groupArm = $arm;
	if ($arm ne 'Placebo') {
		$groupArm = 'BNT162b2 (30 mcg)';
	}
	my $daysBetweenDoseAndCutOff;
	if ($deathDatetime && ($deathCompdate < $unblindingDate)) {
		$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $deathDatetime);
	} else {
		$daysBetweenDoseAndCutOff = time::calculate_days_difference($dose1Datetime, $unblindingDatetime);
	}
	if ($arm eq 'Placebo') {
		$doePlacebo  += $daysBetweenDoseAndCutOff;
	} else {
		$doeBNT162b2 += $daysBetweenDoseAndCutOff;	
	}
	return ($groupArm, $doeBNT162b2, $doePlacebo, $doePlaceboToBNT162b2);
}