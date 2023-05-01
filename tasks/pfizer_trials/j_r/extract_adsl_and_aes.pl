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
my %adaeData       = ();
my %advaData       = ();
my $advaFile       = "public/doc/pfizer_trials/pfizer_adva_patients.json";
my $dt19600101     = '1960-01-01 12:00:00';
my $tp19600101     = time::datetime_to_timestamp($dt19600101);
my $cutoffCompdate = '20210313';

set_columns();

load_adva();

load_adsl_data();

load_adae_data();

print_csv();

sub set_columns {
	@adslColumns
	= (
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
		'saf2fl'
	);
	@adaeColumns
	= (
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
		'astdtf'
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

			my @adslValues = ();
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
					$adslColumn eq 'vax10udt' ||
					$adslColumn eq 'vax20udt' ||
					$adslColumn eq 'unblnddt' ||
					$adslColumn eq 'x1csrdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
					if ($adslColumn eq 'unblnddt') {
						($unblindingDate)   = split ' ', $value;
						$unblindingDate     =~ s/\D//g;
					}
				}
				# say "$adslColumn : $value";
				push @adslValues, $value;
			}

			my $subjid = $values{'subjid'} // die;

			# Verifying phase data (only phase 1 30 mcg are kept).
			my $phase  = $values{'phase'}   // die;
			my $arm    = $values{'arm'}     // die;
			my $age    = $values{'agetr01'} // die;
			unless ($phase eq 'Phase 3' || $phase eq 'Phase 3_ds6000'  || $phase eq 'Phase 2_ds360/ds6000') {
				unless (exists $advaData{$subjid}) {
					next;
				}
				my $actArm = $advaData{$subjid}->{'actArm'} // die;
				next if $actArm ne 'BNT162b2 Phase 1 (30 mcg)';
			}
			next if $age < 16;
			$adslData{$subjid}->{'unblindingDate'} = $unblindingDate;
			$adslData{$subjid}->{'adslValues'}     = \@adslValues;
		}
	}
	close $in;
	$dRNum--;
	say "ADSL:";
	say "total rows        : $dRNum";
	say "subjects          : " . keys %adslData;
}

sub load_adae_data {
	my $missingDays = 0;
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
			next unless exists $adslData{$subjid};
			my $unblindingDate = $adslData{$subjid}->{'unblindingDate'} || $cutoffCompdate;
			# p%values;
			# die;
			my @adaeValues = ();
			my $onsetDate;
			for my $adaeColumn (@adaeColumns) {
				my $value = $values{$adaeColumn} // die "adaeColumn : [$adaeColumn]";
				die if $value =~ /$csvSeparator/;
				# Converting dates.
				if ($value && (
					$adaeColumn eq 'astdt'
				)) {
					$value = $tp19600101 + $value * 86400;
					$value = time::timestamp_to_datetime($value);
					my ($date) = split ' ', $value;
					if ($date) {
						$date =~ s/\D//g;
						if ($date && $date =~ /^........$/) {
							$onsetDate = $date;
						}
					}
				}
				push @adaeValues, $value;
			}
			if ($onsetDate) {
				next unless $onsetDate <= $unblindingDate;
			}
			my $aestdy = $values{'aestdy'}  // die;
			if ($aestdy) {
				die if $aestdy == 999;
			}
			$aestdy    = 999 if length $aestdy == 0;
			my $aeser  = $values{'aeser'}  // die;
			if ($aeser && $aeser eq 'Y') {
				if ($aestdy == 999) {
					$missingDays++;
				}
				$adaeData{$subjid}->{'aeserRows'}++;
				$adaeData{$subjid}->{'adaeValues'}->{$aestdy}->{$dRNum} = \@adaeValues;
			}
		}
	}
	close $in;
	$dRNum--;
	say "ADAE SAEs:";
	say "total rows        : $dRNum";
	say "subjects          : " . keys %adaeData;
	say "rows missing days : $missingDays";
}

sub print_csv {
	open my $out, '>:utf8', 'serious_adverse_effects_raw_data.csv';
	for my $adslColumn (@adslColumns) {
		print $out "$adslColumn$csvSeparator";
	}
	print $out "aeserRows$csvSeparator";
	for my $adaeColumn (@adaeColumns) {
		print $out "$adaeColumn$csvSeparator";
	}
	say $out '';
	for my $subjid (sort{$a <=> $b} keys %adslData) {
		my @adslValues = @{$adslData{$subjid}->{'adslValues'}};
		die unless scalar @adslValues == scalar @adslColumns;
		for my $adslValue (@adslValues) {
			print $out "$adslValue$csvSeparator";
		}
		my $aeserRows  = $adaeData{$subjid}->{'aeserRows'} // 0;
		print $out "$aeserRows$csvSeparator";
		if (exists $adaeData{$subjid}->{'aeserRows'}) {
			for my $aeDay (sort{$a <=> $b} keys %{$adaeData{$subjid}->{'adaeValues'}}) {
				# If we have only one AE on the first day with SAE, printing simplet set of values.
				if (keys %{$adaeData{$subjid}->{'adaeValues'}->{$aeDay}} == 1) {
					for my $dRNum (sort keys %{$adaeData{$subjid}->{'adaeValues'}->{$aeDay}}) {
						my @adaeValues = @{$adaeData{$subjid}->{'adaeValues'}->{$aeDay}->{$dRNum}};
						for my $adaeValue (@adaeValues) {
							print $out "$adaeValue$csvSeparator";
						}
					}
				} else { # Otherwise, solving conflicts : we sustain every seriousness tag set to "Y" and "RELATED" if one SAE is judged so.
					next if $aeDay == 999;
					my (
						$usubjid,
						$aeser,
						$aestdtc,
						$aestdy,
						$aescong,
						$aesdisab,
						$aesdth,
						$aeshosp,
						$aeslife,
						$aesmie,
						$aemeres,
						$aerel,
						$aereln,
						$astdt,
						$astdtf
					);
					for my $dRNum (sort keys %{$adaeData{$subjid}->{'adaeValues'}->{$aeDay}}) {
						my @adaeValues = @{$adaeData{$subjid}->{'adaeValues'}->{$aeDay}->{$dRNum}};
						unless ($usubjid) { # Values 0 to 3 arent subject to potential conflicts and are set simultaneously.
							$usubjid = $adaeValues[0]  // die;
							$aeser   = $adaeValues[1]  // die;
							$aestdtc = $adaeValues[2]  // die;
							$aestdy  = $adaeValues[3]  // die;
							$astdt   = $adaeValues[13] // die;
							$astdtf  = $adaeValues[14] // die;
						}
						my @yNTags = ($adaeValues[4], $adaeValues[5], $adaeValues[6], $adaeValues[7], $adaeValues[8], $adaeValues[9], $adaeValues[10]);
						my $yNN    = 4;
						for my $yNTag (@yNTags) {
							if ($yNTag eq 'Y') {
								if ($yNN == 4) {
									$aescong  = $yNTag;
								} elsif ($yNN == 5) {
									$aesdisab = $yNTag;
								} elsif ($yNN == 6) {
									$aesdth   = $yNTag;
								} elsif ($yNN == 7) {
									$aeshosp  = $yNTag;
								} elsif ($yNN == 8) {
									$aeslife  = $yNTag;
								} elsif ($yNN == 9) {
									$aesmie   = $yNTag;
								} elsif ($yNN == 10) {
									$aemeres  = $yNTag;
								} else { die }
							} else {
								if ($yNN == 4) {
									$aescong  = $yNTag unless $aescong;
								} elsif ($yNN == 5) {
									$aesdisab = $yNTag unless $aesdisab;
								} elsif ($yNN == 6) {
									$aesdth   = $yNTag unless $aesdth;
								} elsif ($yNN == 7) {
									$aeshosp  = $yNTag unless $aeshosp;
								} elsif ($yNN == 8) {
									$aeslife  = $yNTag unless $aeslife;
								} elsif ($yNN == 9) {
									$aesmie   = $yNTag unless $aesmie;
								} elsif ($yNN == 10) {
									$aemeres  = $yNTag unless $aemeres;
								} else { die }
							}
							$yNN++;
						}
						if ($adaeValues[11] eq 'NOT RELATED') {
							unless ($aerel) {
								$aerel  = $adaeValues[11] // die;
								$aereln = $adaeValues[12] // die;
							}
						} else {
							$aerel  = $adaeValues[11] // die;
							$aereln = $adaeValues[12] // die;
						}
					}
					my @adaeValues = (
						$usubjid,
						$aeser,
						$aestdtc,
						$aestdy,
						$aescong,
						$aesdisab,
						$aesdth,
						$aeshosp,
						$aeslife,
						$aesmie,
						$aemeres,
						$aerel,
						$aereln,
						$astdt,
						$astdtf
					);
					for my $adaeValue (@adaeValues) {
						$adaeValue = '' unless defined $adaeValue;
						print $out "$adaeValue$csvSeparator";
					}
				}
				last;
			}
		} else {
			for my $adaeColumn (@adaeColumns) {
				print $out "$csvSeparator";
			}
		}
		say $out '';
	}
}

