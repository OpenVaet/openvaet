

#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $dt19600101  = '1960-01-01 12:00:00';
my $tp19600101  = time::datetime_to_timestamp($dt19600101);
my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
open my $in, '<:utf8', $adslFile;
my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels  = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects    = ();
my %stats       = ();
while (<$in>) {
	chomp $_;
	$dRNum++;

	# Verifying line.
	my $line = $_;
	$line = decode("ascii", $line);
	for (/[^\n -~]/g) {
	    printf "Bad character: %02x\n", ord $_;
	    die;
	}

	# First row = line labels.
	if ($dRNum == 1) {
		my @labels = split ',', $line;
		my $lN = 0;
		for my $label (@labels) {
			$label =~ s/\"//g;
			$dataLabels{$lN} = $label;
			$lN++;
		}
		$expectedValues = keys %dataLabels;
	} else {

		# Verifying we have the expected number of values.
		open my $fh, "<", \$_;
		my $row = $dataCsv->getline ($fh);
		my @row = @$row;
		die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
		my $vN  = 0;
		my %values = ();
		for my $value (@row) {
			my $label = $dataLabels{$vN} // die;
			$values{$label} = $value;
			$vN++;
		}
		# p%values;
		# die;

		# Fetching the data we currently focus on.
		my $trialSiteId       = $values{'SITEID'}   // die;
		my $subjectId         = $values{'SUBJID'}   // die;
		my $cohort            = $values{'COHORT'}   // die;
		my $uSubjectId        = $values{'USUBJID'}  // die;
		my $ageUnit           = $values{'AGETRU01'} // die;
		die unless $ageUnit eq 'YEARS';
		my $ageYears          = $values{'AGETR01'}  // die;
		my $randomNumber      = $values{'RANDNO'}   // die;
		($ageYears) = split '\.', $ageYears;
		die unless $ageYears;
		my $screeningUts      = $values{'RFICDT'}  // die;
		my $randomizationUts  = $values{'RANDDT'}  // die;
		my ($randomizationDatetime, $randomizationDate);
		my ($screeningDatetime, $screeningDate);
		unless ($randomizationUts) {
			$stats{'noRandomizationDate'}++;
		} else {
			$randomizationUts      = $tp19600101 + $randomizationUts * 86400;
			$randomizationDatetime = time::timestamp_to_datetime($randomizationUts);
			($randomizationDate)   = split ' ', $randomizationDatetime;
			$randomizationDate     =~ s/\D//g;
		}
		unless ($screeningUts) {
			$stats{'noScreeningDate'}++;
		} else {
			$screeningUts      = $tp19600101 + $screeningUts * 86400;
			$screeningDatetime = time::timestamp_to_datetime($screeningUts);
			($screeningDate)   = split ' ', $screeningDatetime;
			$screeningDate     =~ s/\D//g;
		}
		my $aai1effl          = $values{'AAI1EFFL'}  // die;
		my $mulenRfl          = $values{'MULENRFL'}  // die;
		my $evaleffl          = $values{'EVALEFFL'}  // die;
		my $unblindingUts     = $values{'UNBLNDDT'}  // die;
		my ($unblindingDatetime, $unblindingDate);
		unless ($unblindingUts) {
			$stats{'noUnblindingDate'}++;
		} else {
			$unblindingUts      = $tp19600101 + $unblindingUts * 86400;
			$unblindingDatetime = time::timestamp_to_datetime($unblindingUts);
			($unblindingDate)   = split ' ', $unblindingDatetime;
			$unblindingDate     =~ s/\D//g;
		}
		if ($randomizationDate) {
			if ($randomizationDate > 20201114) {
				$stats{'randomizationPostCutOff'}->{'total'}++;
			} else {
				$stats{'randomizationPreCutOff'}->{'total'}++;
				if ($ageYears < 16) {
					$stats{'randomizationPreCutOff'}->{'byAges'}->{'under16'}++;
				} else {
					$stats{'randomizationPreCutOff'}->{'byAges'}->{'over16'}++;
				}
			}
		}
		if ($ageYears < 16) {
			$stats{'under16'}++;
		} else {
			$stats{'over16'}++;
		}
		my $hasHIV  = $values{'HIVFL'}  // die;
		if ($hasHIV eq 'Y') {
			$hasHIV = 1;
			$stats{'hasHIV'}++;
		} elsif ($hasHIV eq 'N') {
			$hasHIV = 0;
		} else {
			die;
		}
		my $saffl  = $values{'SAFFL'}  // die;
		my $phase  = $values{'PHASE'}  // die;
		my $arm    = $values{'ARM'}    // die;
		$stats{'byPhasesArms'}->{$phase}->{'total'}++;
		$stats{'byPhasesArms'}->{$phase}->{'byArm'}->{$arm}++;
		my $dose1Uts  = $values{'VAX101DT'}  // die;
		my ($dose1Datetime, $dose1Date);
		unless ($dose1Uts) {
			$stats{'noDose1Date'}++;
		} else {
			$dose1Uts      = $tp19600101 + $dose1Uts * 86400;
			$dose1Datetime = time::timestamp_to_datetime($dose1Uts);
			($dose1Date)   = split ' ', $dose1Datetime;
			$dose1Date     =~ s/\D//g;
		}
		my $dose2Uts  = $values{'VAX102DT'}  // die;
		my ($dose2Datetime, $dose2Date);
		unless ($dose2Uts) {
			$stats{'noDose2Date'}++;
		} else {
			$dose2Uts      = $tp19600101 + $dose2Uts * 86400;
			$dose2Datetime = time::timestamp_to_datetime($dose2Uts);
			($dose2Date)   = split ' ', $dose2Datetime;
			$dose2Date     =~ s/\D//g;
		}
		if ($dose1Date) {
			if ($dose1Date > 20201114) {
				$stats{'dose1PostCutOff'}->{'total'}++;
			} else {
				$stats{'dose1PreCutOff'}->{'total'}++;
				if ($ageYears < 16) {
					$stats{'dose1PreCutOff'}->{'byAges'}->{'under16'}++;
				} else {
					$stats{'dose1PreCutOff'}->{'byAges'}->{'over16'}++;
				}
			}
		}
		my $dose3Uts  = $values{'VAX201DT'}  // die;
		my ($dose3Datetime, $dose3Date);
		unless ($dose3Uts) {
			$stats{'noDose2Date'}++;
		} else {
			$dose3Uts      = $tp19600101 + $dose3Uts * 86400;
			$dose3Datetime = time::timestamp_to_datetime($dose3Uts);
			($dose3Date)   = split ' ', $dose3Datetime;
			$dose3Date     =~ s/\D//g;
		}
		my $dose4Uts  = $values{'VAX202DT'}  // die;
		my ($dose4Datetime, $dose4Date);
		unless ($dose4Uts) {
			$stats{'noDose2Date'}++;
		} else {
			$dose4Uts      = $tp19600101 + $dose4Uts * 86400;
			$dose4Datetime = time::timestamp_to_datetime($dose4Uts);
			($dose4Date)   = split ' ', $dose4Datetime;
			$dose4Date     =~ s/\D//g;
		}
		if ($dose1Date) {
			if ($dose1Date > 20201114) {
				$stats{'dose1PostCutOff'}->{'total'}++;
			} else {
				$stats{'dose1PreCutOff'}->{'total'}++;
				if ($ageYears < 16) {
					$stats{'dose1PreCutOff'}->{'byAges'}->{'under16'}++;
				} else {
					$stats{'dose1PreCutOff'}->{'byAges'}->{'over16'}++;
				}
			}
		}
		my $sex             = $values{'SEX'}     // die;
		my $deathUts        = $values{'DTHDT'}   // die;
		my $covidAtBaseline = $values{'COVBLST'} // die;
		my ($deathDate, $deathDatetime);
		if ($deathUts) {
			$deathUts       = $tp19600101 + $deathUts * 86400;
			$deathDatetime  = time::timestamp_to_datetime($deathUts);
			($deathDate)    = split ' ', $deathDatetime;
			$deathDate      =~ s/\D//g;
			# say $deathDate;
			# die;
		}
		if ($sex eq 'M') {
			$sex = 'Male';
		} elsif ($sex eq 'F') {
			$sex = 'Female';
		} else {
			die;
		}
		# say "subjectId         : $subjectId";
		# say "randomizationDatetime : $randomizationDatetime";
		# die;
		$subjects{$subjectId}->{'totalADSLRows'}++;
		my $totalADSLRows     = $subjects{$subjectId}->{'totalADSLRows'} // die;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'trialSiteId'}           = $trialSiteId;
		$subjects{$subjectId}->{'randomNumber'}          = $randomNumber;
		$subjects{$subjectId}->{'uSubjectId'}            = $uSubjectId;
		$subjects{$subjectId}->{'aai1effl'}              = $aai1effl;
		$subjects{$subjectId}->{'cohort'}                = $cohort;
		$subjects{$subjectId}->{'mulenRfl'}              = $mulenRfl;
		$subjects{$subjectId}->{'evaleffl'}              = $evaleffl;
		$subjects{$subjectId}->{'screeningDatetime'}     = $screeningDatetime;
		$subjects{$subjectId}->{'screeningDate'}         = $screeningDate;
		$subjects{$subjectId}->{'randomizationDatetime'} = $randomizationDatetime;
		$subjects{$subjectId}->{'randomizationDate'}     = $randomizationDate;
		$subjects{$subjectId}->{'covidAtBaseline'}       = $covidAtBaseline;
		$subjects{$subjectId}->{'unblindingDatetime'}    = $unblindingDatetime;
		$subjects{$subjectId}->{'unblindingDate'}        = $unblindingDate;
		$subjects{$subjectId}->{'deathDatetime'}         = $deathDatetime;
		$subjects{$subjectId}->{'deathDate'}             = $deathDate;
		$subjects{$subjectId}->{'dose1Datetime'}         = $dose1Datetime;
		$subjects{$subjectId}->{'dose1Date'}             = $dose1Date;
		$subjects{$subjectId}->{'dose2Datetime'}         = $dose2Datetime;
		$subjects{$subjectId}->{'dose2Date'}             = $dose2Date;
		$subjects{$subjectId}->{'dose3Datetime'}         = $dose3Datetime;
		$subjects{$subjectId}->{'dose3Date'}             = $dose3Date;
		$subjects{$subjectId}->{'dose4Datetime'}         = $dose4Datetime;
		$subjects{$subjectId}->{'dose4Date'}             = $dose4Date;
		$subjects{$subjectId}->{'hasHIV'}                = $hasHIV;
		$subjects{$subjectId}->{'ageYears'}              = $ageYears;
		$subjects{$subjectId}->{'saffl'}                 = $saffl;
		$subjects{$subjectId}->{'phase'}                 = $phase;
		$subjects{$subjectId}->{'arm'}                   = $arm;
		$subjects{$subjectId}->{'sex'}                   = $sex;
		# p$subjects{$subjectId};
		# die;
	}
}
close $in;
$dRNum--;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;
p%stats;
my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_adsl_patients.json";
print $out encode_json\%subjects;
close $out;