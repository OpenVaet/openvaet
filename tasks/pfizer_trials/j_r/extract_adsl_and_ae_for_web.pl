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

my $csvSeparator = ';';

my (@adslColumns,
	@adaeColumns);
  
my %adslData       = ();
my %devData        = ();
my %advaData       = ();
my $advaFile       = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $pcrRecordsFile = 'public/doc/pfizer_trials/pfizer_mb_patients.json';
my $devData        = "public/doc/pfizer_trials/deviations_data_currated.json";
my $dt19600101     = '1960-01-01 12:00:00';
my $tp19600101     = time::datetime_to_timestamp($dt19600101);
my $cutoffCompdate = '20210313';

my %pcrRecords     = ();
my %stats          = ();

set_columns();

load_adva();

load_pcr_tests();

load_supp_dv();

load_adsl_data();

load_adae_data();

print_json();

sub set_columns {
	@adslColumns
	= (
		'subjid',
		'usubjid',
		'age',
		'agetr01',
		'agegr1',
		'agegr1n',
		'race',
		'racen',
		'ethnic',
		'ethnicn',
		'arace',
		'aracen',
		'racegr1',
		'racegr1n',
		'sex',
		'sexn',
		'country',
		'saffl',
		'actarm',
		'actarmcd',
		'trtsdt',
		'vax101dt',
		'vax102dt',
		'vax201dt',
		'vax202dt',
		'vax10udt',
		'vax20udt',
		'reactofl',
		'phase',
		'phasen',
		'unblnddt',
		'bmicat',
		'bmicatn',
		'combodfl',
		'covblst',
		'hivfl',
		'x1csrdt',
		'saf1fl',
		'saf2fl',
		'dthdt'
	);
	@adaeColumns
	= (
		'subjid',
		'usubjid',
		'aeser',
		'aestdtc',
		'aestdy',
		'aescong',
		'aesdisab',
		'aesdth',
		'aeshosp',
		'aeslife',
		'aesmie',
		'aemeres',
		'aerel',
		'aereln',
		'astdt',
		'astdtf',
		'aehlgt',
		'aehlt'
	);
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

sub load_supp_dv {
	open my $in, '<:utf8', $devData or die "Missing file [$devData]";
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%devData = %$json;
	say "[$devData] -> patients : " . keys %devData;
}

sub load_adsl_data {
	my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
	die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
	open my $in, '<:utf8', $adslFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
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
			$line = lc $line;
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
			my $subjid = $values{'subjid'} // die;
			my $unblindingDate;
			for my $adslColumn (@adslColumns) {
				my $value = $values{$adslColumn} // die "adslColumn : [$adslColumn]";
				die if $value =~ /$csvSeparator/;
				# Converting dates.
				if ($value && (
					$adslColumn eq 'vax101dt' ||
					$adslColumn eq 'vax102dt' ||
					$adslColumn eq 'vax201dt' ||
					$adslColumn eq 'vax202dt' ||
					$adslColumn eq 'trtsdt'   ||
					$adslColumn eq 'vax10udt' ||
					$adslColumn eq 'vax20udt' ||
					$adslColumn eq 'unblnddt' ||
					$adslColumn eq 'x1csrdt'  ||
					$adslColumn eq 'dthdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
					if ($adslColumn eq 'unblnddt') {
						($unblindingDate)   = split ' ', $value;
						$unblindingDate     =~ s/\D//g;
					}
				}
				$adslData{$subjid}->{$adslColumn} = $value;
			}
			my $actArm = $advaData{$subjid}->{'actArm'};
			$adslData{$subjid}->{'adva.actarm'} = $actArm;
			if (exists $devData{$subjid}) {
				for my $dvspid (sort keys %{$devData{$subjid}}) {
					$adslData{$subjid}->{'deviations'}->{$dvspid} = \%{$devData{$subjid}->{$dvspid}};
				}
			} else {
				$adslData{$subjid}->{'deviations'} = {};
			}

			# Loading subject's tests.
			subject_central_pcrs_by_visits($subjid);
			subject_central_nbindings_by_visits($subjid);
		}
	}
	close $in;
	$dRNum--;
	say "ADSL:";
	say "total rows        : $dRNum";
	say "subjects          : " . keys %adslData;
}

sub load_adae_data {
	my $adaeFile   = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv";
	die "you must convert the adae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv] first." unless -f $adaeFile;
	open my $in, '<:utf8', $adaeFile;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
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
			$line = lc $line;
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
			my $subjid = $values{'subjid'}  // die;
			die unless exists $adslData{$subjid};
			my $aestdy = $values{'aestdy'}  // die;
			if ($aestdy) {
				die if $aestdy == 999;
			}
			$aestdy    = 999 if length $aestdy == 0;
			for my $adaeColumn (@adaeColumns) {
				my $value = $values{$adaeColumn} // die "adaeColumn : [$adaeColumn]";
				die if $value =~ /$csvSeparator/;
				# Converting dates.
				if ($value && (
					$adaeColumn eq 'astdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
				}
				$adslData{$subjid}->{'adaeRows'}->{$dRNum}->{$adaeColumn} = $value;
			}
		}
	}
	close $in;
	$dRNum--;
	say "ADAE SAEs:";
	say "total rows        : $dRNum";
}

sub print_json {
	open my $out, '>:utf8', 'adverse_effects_raw_data.json';
	print $out encode_json\%adslData;
	close $out;
}

sub subject_central_pcrs_by_visits {
	my ($subjid) = @_;
	for my $visitDate (sort keys %{$pcrRecords{$subjid}->{'mbVisits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'};
		my $visitCompdate = $visitDate;
		$visitCompdate    =~ s/\D//g;

		my $mborres = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'Cepheid RT-PCR assay for SARS-CoV-2'}->{'mbResult'} // die;
		my $visit = $pcrRecords{$subjid}->{'mbVisits'}->{$visitDate}->{'visit'} // die;
		if (exists $adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'} && ($adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'} ne $mborres)) {
			next unless $mborres eq 'POS'; # If several conflicting tests on the same date, we only sustain the last positive one.
		}
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'visitdt'}   = $visitDate;
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'mborres'}   = $mborres;
		$adslData{$subjid}->{'pcrs'}->{$visit}->{'visitcpdt'} = $visitCompdate;
	}
}

sub subject_central_nbindings_by_visits {
	my ($subjid) = @_;
	for my $visit (sort keys %{$advaData{$subjid}->{'visits'}}) {

		# Skips the visits unless it contains PCRs.
		next unless exists $advaData{$subjid}->{'visits'}->{$visit}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'};
		# p$advaData{$subjid}->{'visits'}->{$visit};
		# die;
		my $avalc     = $advaData{$subjid}->{'visits'}->{$visit}->{'tests'}->{'N-binding antibody - N-binding Antibody Assay'} // die;
		my $visitcpdt = $advaData{$subjid}->{'visits'}->{$visit}->{'visitDate'}     // die;
		my $visitdt   = $advaData{$subjid}->{'visits'}->{$visit}->{'visitDatetime'} // die;
		if (exists $adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'} && ($adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'} ne $avalc)) {
			next unless $avalc eq 'POS'; # If several conflicting tests on the same date, we only sustain the last positive one.
		}
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'visitdt'}   = $visitdt;
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'avalc'}     = $avalc;
		$adslData{$subjid}->{'nBindings'}->{$visit}->{'visitcpdt'} = $visitcpdt;
	}
}

p%stats;