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
use lib "$FindBin::Bin/../../../lib";
use time;

my $dt19600101 = '1960-01-01 12:00:00';
my $tp19600101 = time::datetime_to_timestamp($dt19600101);

my %subjects   = ();
my %adae       = ();
my %adva       = ();
my %mb         = ();

load_adva();
load_mb();
load_adae();
load_adsl();

sub load_adva {
	my $advaFile   = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0123168-to-0126026_125742_S1_M5_c4591001-A-D-adva.csv";
	die "you must convert the adva file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0123168-to-0126026_125742_S1_M5_c4591001-A-D-adva.csv] first." unless -f $advaFile;
	open my $in, '<:utf8', $advaFile;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels = ();
	my ($dRNum,
		$expectedValues,
		$noDose1Data) = (0, 0, 0);
	while (<$in>) {
		$dRNum++;

		# Verifying line.
		chomp $_;
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

			# Fetching the data we currently focus on.
			my $subjid      = $values{'SUBJID'}  // die;
			my $usubjid     = $values{'USUBJID'} // die;
			my $siteid      = $values{'SITEID'}  // die;
			my $adt         = $values{'ADT'}     // die;
			$adt            = $tp19600101 + $adt * 86400;
			$adt            = time::timestamp_to_datetime($adt);
			my $unblindDt   = $values{'UNBLNDDT'};
			my $unblindDatetime;
			if ($unblindDt) {
				$unblindDt  = $tp19600101 + $unblindDt * 86400;
				$unblindDatetime = time::timestamp_to_datetime($unblindDt);
			}
			my ($visitDate) = split ' ', $adt;
			$visitDate      =~ s/\D//g;
			my $phase       = $values{'PHASE'}    // die;
			my $isdtc       = $values{'ISDTC'}    // die;
			my $visit       = $values{'VISIT'}    // die;
			my $visitnum    = $values{'VISITNUM'} // die;
			die unless $visitnum && looks_like_number $visitnum;
			my $actarm      = $values{'ACTARM'}   // die;
			my $avisit      = $values{'AVISIT'}   // die;
			my $avisitn     = $values{'AVISITN'}  // die;
			my $cohort      = $values{'COHORT'}   // die;
			my $param       = $values{'PARAM'}    // die;
			my $avalc       = $values{'AVALC'}    // die;
			if (
				$param eq 'COVID-19 S1 IgG (U/mL) - Luminex Immunoassay' ||
				$param eq 'SARS-CoV-2 serum neutralizing titer 50 (titer) - Virus Neutralization Assay' ||
				$param eq 'SARS-CoV-2 serum neutralizing titer 90 (titer) - Virus Neutralization Assay'
			) {
				next;
			} else {
				$adva{$subjid}->{'visits'}->{$visit}->{'tests'}->{$param} = $avalc;
			}
			$adva{$subjid}->{'actarm'} = $actarm;
			$adva{$subjid}->{'phase'}  = $phase;
			$adva{$subjid}->{'cohort'} = $cohort;
			$adva{$subjid}->{'visits'}->{$visit}->{'visitnum'}  = $visitnum;
			$adva{$subjid}->{'visits'}->{$visit}->{'avisitn'}   = $avisitn if $avisitn;
			$adva{$subjid}->{'visits'}->{$visit}->{'avisit'}    = $avisit  if $avisit;
			$adva{$subjid}->{'visits'}->{$visit}->{'visitDate'} = $visitDate;
			$adva{$subjid}->{'visits'}->{$visit}->{'adt'}       = $adt;
			$adva{$subjid}->{'totalAdvaRows'}++;
		}
	}
	close $in;
	say "ADVA rows           : $dRNum";
	say "Subjects            : " . keys %adva;
}

sub load_mb {
	my $mbFile     = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282366-to-0285643_125742_S1_M5_c4591001-S-D-mb.csv";
	die "you must convert the mb file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282366-to-0285643_125742_S1_M5_c4591001-S-D-mb.csv] first." unless -f $mbFile;
	open my $in, '<:utf8', $mbFile;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	while (<$in>) {
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
			# die;

			# Fetching the data we currently focus on.
			# p%values;
			# die;
			my $usubjid     = $values{'USUBJID'}  // die;
			my ($subjid)    = $usubjid =~ /^C4591001 .... (.*)$/;
			die unless $subjid && $subjid =~ /^........$/;
			my $mbdtc       = $values{'MBDTC'}    // die;
			$mbdtc          =~ s/T/ /;
			my ($mbdate, $mbhour) = split ' ', $mbdtc;
			my $mbnam       = $values{'MBNAM'}    // die;
			my $mborres     = $values{'MBORRES'}  // die;
			my $visit       = $values{'VISIT'}    // die;
			my $mbmethod    = $values{'MBMETHOD'} // die;
			my $mbtest      = $values{'MBTEST'}   // die;
			next unless $mbtest eq 'Cepheid RT-PCR assay for SARS-CoV-2';
			my $mbstat      = $values{'MBSTAT'}   // die;
			my $spdevid     = $values{'SPDEVID'}  // die;
			unless ($visit) {
				p%values;
				next;
			}
			die unless $mbtest;
			unless ($mborres) {
				die unless $mbstat && $mbstat eq 'NOT DONE';
			}
			if (exists $mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mborres'}) {
				die unless $mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mborres'} eq $mborres;
			}
			$mb{$subjid}->{'subjid'}  = $subjid;
			$mb{$subjid}->{'usubjid'} = $usubjid;
			$mb{$subjid}->{'usubjids'}->{$usubjid} = 1;
			$mb{$subjid}->{'visits'}->{$visit}->{'mbdate'} = $mbdate;
			if ($mbhour) {
				$mb{$subjid}->{'visits'}->{$visit}->{'mbhour'} = $mbhour;
				if (exists $mb{$subjid}->{'visits'}->{$visit}->{'mbhour'}) {
					die unless $mb{$subjid}->{'visits'}->{$visit}->{'mbhour'} eq $mbhour;
				}
			}
			$mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'spdevid'}  = $spdevid;
			$mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mbstat'}   = $mbstat;
			$mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mborres'}  = $mborres;
			$mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mbmethod'} = $mbmethod;
			$mb{$subjid}->{'visits'}->{$visit}->{'tests'}->{$mbtest}->{'mbnam'}    = $mbnam;
			$mb{$subjid}->{'mbrows'}++;
		}
	}
	close $in;
	say "MB rows             : $dRNum";
	say "patients            : " . keys %mb;
}

sub load_adae {
	my $adaeFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv";
	die "you must convert the adae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv] first." unless -f $adaeFile;
	open my $in, '<:utf8', $adaeFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	my %subjects    = ();
	my %noDates     = ();
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
			# open my $out, '>:utf8', 'sample_ae.json';
			# print $out encode_json\%values;
			# close $out;
			# p%values;
			# die;

			# Fetching the data we currently focus on.
			my $subjid            = $values{'SUBJID'}   // die;
			my $usubjid           = $values{'USUBJID'}  // die;
			my $vphase            = $values{'VPHASE'}   // die;
			my $aperioddc         = $values{'APERIODC'} // die;
			my $relation          = $values{'AREL'}     // die;
			my $aehlgt            = $values{'AEHLGT'}   // die;
			my $aehlt             = $values{'AEHLT'}    // die;
			my $aeser             = $values{'AESER'}    // die;
			my $aereltxt          = $values{'AERELTXT'} // die;
			my $atoxgr            = $values{'ATOXGR'}   // die;
			$atoxgr               =~ s/GRADE //;
			my $astdt             = $values{'ASTDT'}    // die;
			if ($astdt) {
				$astdt = $tp19600101 + $astdt * 86400;
				$astdt = time::timestamp_to_datetime($astdt);
			}
			my $aestdtc           = $values{'AESTDTC'}  // die;
			my $aeenddt           = $values{'AEENDTC'}  // die;
			$aestdtc              =~ s/T/ /;
			my $aeterm            = $values{'AETERM'}   // die;
			my ($aecpdt) = split ' ', $aestdtc;
			if ($aecpdt) {
				$aecpdt =~ s/\D//g;
				my ($aeY, $aeM, $aeD) = $aecpdt =~ /(....)(..)(..)/;
				unless ($aeY && $aeM && $aeD) {
					$aecpdt = undef;
				}
			}
			$adae{$subjid}->{'adaeRows'}++;
			$adae{$subjid}->{'usubjids'}->{$usubjid} = 1;
			$adae{$subjid}->{'usubjid'} = $usubjid;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aecpdt'} = $aecpdt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'atoxgr'} = $atoxgr;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aestdtc'} = $aestdtc;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aehlgt'} = $aehlgt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aeterm'} = $aeterm;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aehlt'} = $aehlt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'astdt'} = $astdt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aeser'} = $aeser;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aereltxt'} = $aereltxt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aeenddt'} = $aeenddt;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'aperioddc'} = $aperioddc;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'relation'} = $relation;
			$adae{$subjid}->{'aes'}->{$dRNum}->{'vphase'} = $vphase;
			# p$adae{$subjid};
			# die;
		}
	}
	close $in;
	$dRNum--;
	say "ADAE rows           : $dRNum";
	say "Subjects            : " . keys %adae;
}

sub load_adsl {
	my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
	die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
	open my $in, '<:utf8', $adslFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	my %stats   = ();
	my %subjaes = ();
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

			# Retrieve & apply the documented filters.
			# ADSL.PHASEN>1 and ADSL.AGEGR1N>1 and
			# ADSL.SAFFL="Y" and ADSL.MULENRFL^="Y" and
			# ADSL.HIVFL^="Y" and ADSL.TRT01A^=""
			my $subjid   = $values{'SUBJID'}   // die;
			my $actarm   = $values{'ACTARM'}   // die;
			if ($actarm ne 'Placebo') {
				$actarm  = 'BNT162b2 (30 mcg)';
			}
			my $phasen   = $values{'PHASEN'}   // die;
			my $agegr1n  = $values{'AGEGR1N'}  // die;
			my $saffl    = $values{'SAFFL'}    // die;
			my $mulenrfl = $values{'MULENRFL'} // die;
			my $hivfl    = $values{'HIVFL'}    // die;
			my $trt01a   = $values{'TRT01A'}   // die;

			next unless $phasen  > 1;  # ADSL.PHASEN>1
			next unless $agegr1n > 1;  # and ADSL.AGEGR1N>1
			next unless $saffl eq 'Y'; # and ADSL.SAFFL="Y"
			next if $mulenrfl  eq 'Y'; # and ADSL.MULENRFL^="Y"
			next if $hivfl     eq 'Y'; # and ADSL.HIVFL^="Y"
			next unless $trt01a;       # and ADSL.TRT01A^=""

			my $covblst  = $values{'COVBLST'}  // die;
			$stats{'COVBLSTSplit'}->{$covblst}++;
			my $nBindingV1 = $adva{$subjid}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'}  || 'MIS';
			my $pcrV1      = $mb{$subjid}->{'visits'}->{'V1_DAY1_VAX1_L'}->{'tests'}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mborres'} || 'MIS';
			$stats{'TestsOnCOVBLST'}->{'N-binding'}->{$covblst}->{$nBindingV1}++;
			$stats{'TestsOnCOVBLST'}->{'PCRs'}->{$covblst}->{$pcrV1}++;
			$stats{'TestsOnCOVBLST'}->{'N-binding + PCRs'}->{$covblst}->{$nBindingV1}->{$pcrV1}++;
			$subjects{$subjid}->{'covblst'} = $covblst;

			# Loading doses dates.
			my $vax101dt  = $values{'VAX101DT'} // die;
			my ($vax101cpdt, $vax102cpdt, $vax201cpdt, $vax202cpdt);
			if ($vax101dt) {
				$vax101dt = $tp19600101 + $vax101dt * 86400;
				$vax101dt = time::timestamp_to_datetime($vax101dt);
				($vax101cpdt) = split ' ', $vax101dt;
				$vax101cpdt   =~ s/\D//g;
			}
			my $vax102dt  = $values{'VAX102DT'} // die;
			if ($vax102dt) {
				$vax102dt = $tp19600101 + $vax102dt * 86400;
				$vax102dt = time::timestamp_to_datetime($vax102dt);
				($vax102cpdt) = split ' ', $vax102dt;
				$vax102cpdt   =~ s/\D//g;
			}
			my $vax201dt  = $values{'VAX201DT'} // die;
			if ($vax201dt) {
				$vax201dt = $tp19600101 + $vax201dt * 86400;
				$vax201dt = time::timestamp_to_datetime($vax201dt);
				($vax201cpdt) = split ' ', $vax201dt;
				$vax201cpdt   =~ s/\D//g;
			}
			my $vax202dt  = $values{'VAX202DT'} // die;
			if ($vax202dt) {
				$vax202dt = $tp19600101 + $vax202dt * 86400;
				$vax202dt = time::timestamp_to_datetime($vax202dt);
				($vax202cpdt) = split ' ', $vax202dt;
				$vax202cpdt   =~ s/\D//g;
			}


			# Integrating visit 1 PCR & N-Binding results.
			# p$adva{$subjid};die;
			# p$mb{$subjid}->{'visits'};
			# die;
			my %doseDates    = ();
			die unless $vax101dt;
			$doseDates{'1'}  = $vax101dt;
			$doseDates{'2'}  = $vax102dt if $vax102dt;
			$doseDates{'3'}  = $vax201dt if $vax201dt;
			$doseDates{'4'}  = $vax202dt if $vax202dt;
			if (exists $adae{$subjid}) {
				my ($aes, $saes) = (0, 0);
				for my $aeNum (sort{$a <=> $b} keys %{$adae{$subjid}->{'aes'}}) {
					my $aeser = $adae{$subjid}->{'aes'}->{$aeNum}->{'aeser'} // die;
					my $astdt = $adae{$subjid}->{'aes'}->{$aeNum}->{'astdt'} // die;
					my ($aeY, $aeM, $aeD) = $astdt =~ /(....)-(..)-(..)/;
					my $aeCompdate = "$aeY$aeM$aeD";
					my %doseDatesByDates  = ();
					for my $dNum (sort{$a <=> $b} keys %doseDates) {
						my $dt = $doseDates{$dNum} // die;
						my ($dosecpdt) = split ' ', $dt;
						$dosecpdt =~ s/\D//g;
						next unless $dosecpdt <= $aeCompdate;
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
					my $doseArm = $actarm;
					if ($closestDose > 2) {
						$doseArm = 'Placebo -> BNT162b2 (30 mcg)';
					}
					$aes++;
					unless ($closestDose) {
						$doseArm = 'No dose yet';
					}
					if ($aeser eq 'Y') {
						$saes++;
						unless (exists $subjaes{$subjid}->{$doseArm}->{'saes'}) {
							$subjaes{$subjid}->{$doseArm}->{'saes'} = 1;
							$stats{'SubjectsWithAEsCOVBLST'}->{$covblst}->{$doseArm}->{'saes'}++;
						}
						$stats{'AEsCOVBLST'}->{$covblst}->{$doseArm}->{'saes'}++;
					}
					# say "closestDose: $closestDose";
					# say "doseArm    : $doseArm";
					# say "aeser      : $aeser";
					unless (exists $subjaes{$subjid}->{$doseArm}->{'aes'}) {
						$subjaes{$subjid}->{$doseArm}->{'aes'} = 1;
						$stats{'SubjectsWithAEsCOVBLST'}->{$covblst}->{$doseArm}->{'aes'}++;
					}
					$stats{'AEsCOVBLST'}->{$covblst}->{$doseArm}->{'aes'}++;
				}
				# p$adae{$subjid};
				# die;
			}
			# p$adae{$subjid};
			# die;
		}
	}
	close $in;
	$dRNum--;
	say "ADSL rows           : $dRNum";
	say "Subjects            : " . keys %subjects;
	say "COVBLST repartition :";
	p$stats{'COVBLSTSplit'};
	say "Tests repartition   :";
	p$stats{'TestsOnCOVBLST'};
	say "Subjects with AEs   :";
	p$stats{'SubjectsWithAEsCOVBLST'};
	say "AEs reported        :";
	p$stats{'AEsCOVBLST'};
}