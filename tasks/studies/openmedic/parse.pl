#!/usr/bin/perl
use strict;
use warnings;
use v5.30;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use File::stat;
use JSON;
use Math::Round qw(nearest);
use Scalar::Util qw(looks_like_number);
use Encode;
use Encode::Unicode;
use FindBin;
use lib "$FindBin::Bin/../../../lib";

# Project's libraries.
use time;

# Source OpenMedic : https://www.data.gouv.fr/en/datasets/open-medic-base-complete-sur-les-depenses-de-medicaments-interregimes/
# Source Medic'AM  : https://assurance-maladie.ameli.fr/etudes-et-donnees/open-data-depenses-sante-soins-ville-2021

my @years   = (2016, 2017, 2018, 2019, 2020, 2021); # The yearly files we expect to find in the [tasks/studies/openmedic] folder.
my %sexes   = (); # Hash storing the sex enums to values.
$sexes{'1'} = 'Masculin';
$sexes{'2'} = 'Féminin';
$sexes{'9'} = 'Inconnu';

my $drugsPublicFile = 'public/doc/openmedic/openmedic_selected_chemical_substances.csv';
my $openMedicFolder = 'tasks/studies/openmedic';
my $drugsConfigFile = "$openMedicFolder/config.csv";
my %drugs = ();

load_config();

parse_medicam_semester_files();

parse_open_medic_yearly_files();

sub load_config {
	my $lNum = 0;
	open my $in, '<:utf8', $drugsConfigFile;
	open my $out, '>:utf8', $drugsPublicFile;
	while (<$in>) {
		$lNum++;
		chomp $_;
		if ($lNum != 1) {
			my $line  = lc $_;
			my @elems = split ';', $line;
			my $anatomicMainGroup         = $elems[0] // die;
			my $chemicalSubGroup          = $elems[2] // die;
			my $chemicalSubstanceSubGroup = $elems[4] // die;
			$drugs{$chemicalSubstanceSubGroup}->{'anatomicMainGroup'} = $anatomicMainGroup;
			$drugs{$chemicalSubstanceSubGroup}->{'chemicalSubGroup'}  = $chemicalSubGroup;
		}
		say $out $_;
	}
	close $in;
	close $out;
	# p%drugs;
	# die;
}

sub parse_medicam_semester_files {
	my %stats       = ();
	for my $file (glob "tasks/studies/openmedic/Medicam/csv/*") {
		my %dataLabels = ();
		my ($year, $semester) = $file =~ /Medicam\/csv\/(.*)_Semestre_(.*)\.csv/;
		say "file     : $file";
		say "year     : $year";
		say "semester : $semester";
		die unless $year && ($semester == 1 || $semester == 2);
		my @months = ();
		if ($semester == 1) {
			@months = ('01', '02', '03', '04', '05', '06');
		} else {
			@months = ('07', '08', '09', '10', '11', '12');
		}
		# die;
		open my $in, '<:utf8', $file;
		my $lNum = 0;
		# open my $out, '>:utf8', 'strip.txt';
		while (<$in>) {
			$lNum++;
			chomp $_;
			my $line       = lc $_;
			if ($lNum == 1) {
				my @labels = split ';', $line;
				my $labNum = 0;
				for my $label (@labels) {
					$labNum++;
					$dataLabels{$labNum} = $label;
				}
			} else {
				my @values = split ';', $line;
				my $vNum   = 0;
				my %values = ();
				for my $value (@values) {
					$vNum++;
					my $label = $dataLabels{$vNum} // die;
					$values{$label} = $value;
				}
				next unless keys %values;
				# p%values;
				# die;
				my $chemicalSubstanceSubGroup = $values{'"classeatc"'} // next;
				my $product = $values{'produit'} // die;
				if (exists $drugs{$chemicalSubstanceSubGroup}) {
					for my $month (@months) {
						my $boites = $values{"\"nombre de boites remboursées $year-$month\""} // next;
						my $refundBasis = $values{"\"base de remboursement $year-$month\""} // $values{"base de remboursement $year-$month"} // die;
						my $anatomicMainGroup = $drugs{$chemicalSubstanceSubGroup}->{'anatomicMainGroup'} // die;
						$refundBasis =~ s/ €//;
						$refundBasis =~ s/ //g;
						$boites =~ s/ //g;
						# say "month    : $month";
						# say "boites   : $boites";
						# say "refundBasis   : $refundBasis";
						# say $out "[$refundBasis]";
						# die;
						$stats{'medicam'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{$month}->{'totalLines'}++;
						$stats{'medicam'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{$month}->{'totalPacks'}  += $boites;
						$stats{'medicam'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{$month}->{'refundBasis'} += $refundBasis;
					}
				}
			}
		}
		close $in;
		# close $out;
	}

	# Printing statistics.
	open my $out, '>:utf8', 'stats/medicam_stats.json';
	print $out encode_json\%stats;
	close $out;

	# p%stats;
}

sub parse_open_medic_yearly_files {
	my %cats        = ();
	my %ages        = ();
	my %stats       = ();
	for my $year (@years) {
		my %dataLabels = ();
		my $file = "tasks/studies/openmedic/OPEN_MEDIC_$year.csv";
        die unless -f $file;
        my $fileStats = stat($file);
        $stats{'openMedic'}->{'byYears'}->{$year}->{'file'} = $file;
        $stats{'openMedic'}->{'byYears'}->{$year}->{'fileSize'} = nearest(0.01, $fileStats->size / 1000000);
		STDOUT->printflush("\rParsing [$year] data - Opening File          ");
		open my $in, '<:utf8', $file or die "Missing yearly file : $!";
		my ($lNum, $cpt) = (0, 0);
		while (<$in>) {
			$lNum++;
			chomp $_;
			my $line       = lc $_;
			if ($lNum == 1) {
				my @labels = split ';', $line;
				my $labNum = 0;
				for my $label (@labels) {
					$labNum++;
					$dataLabels{$labNum} = $label;
				}
			} else {
				my @values = split ';', $line;
				my $vNum   = 0;
				my %values = ();
				for my $value (@values) {
					$vNum++;
					my $label = $dataLabels{$vNum} // die;
					$values{$label} = $value;
				}
				my $anatomicMainGroup         = $values{'l_atc1'} // die;
				my $therapeuticalSubGroup     = $values{'l_atc2'} // die;
				my $chemicalSubGroup          = $values{'l_atc3'} // die;
				my $pharmaceuticalSubGroup    = $values{'l_atc4'} // die;
				my $chemicalSubstanceSubGroup = $values{'l_atc5'} // die;
				$cats{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$pharmaceuticalSubGroup}->{$chemicalSubGroup}->{$chemicalSubstanceSubGroup}++;
				my $age                       = $values{'age'}    // die;
				$ages{$age} = 1;
				my $ageGroup                  = age_to_age_group($age);
				next unless $ageGroup eq '0 - 19 ans';
				my $totalPacks                = $values{'boites'} // die;
				my $sex                       = $values{'sexe'}   // die;
				my $sexName                   = $sexes{$sex}      // die;
				my $refundBasis               = $values{'bse'}    // die;
				$refundBasis                  =~ s/\.//;
				$refundBasis                  =~ s/,/\./;
				if (exists $drugs{$chemicalSubstanceSubGroup}) {
					# say "anatomicMainGroup         : $anatomicMainGroup";
					# say "therapeuticalSubGroup     : $therapeuticalSubGroup";
					# say "chemicalSubGroup          : $chemicalSubGroup";
					# say "chemicalSubstanceSubGroup : $chemicalSubstanceSubGroup";
					# say "sex                       : $sex";
					# say "sexName                   : $sexName";
					# say "age                       : $age";
					# say "ageGroup                  : $ageGroup";
					# say "totalPacks                : $totalPacks";
					# say "refundBasis               : $refundBasis";
					# p%values;
					$stats{'openMedic'}->{'byYears'}->{$year}->{'totalLines'}++;
					$stats{'openMedic'}->{'byYears'}->{$year}->{'totalPacks'}  += $totalPacks;
					$stats{'openMedic'}->{'byYears'}->{$year}->{'refundBasis'} += $refundBasis;
					$stats{'openMedic'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{'totalLines'}++;
					$stats{'openMedic'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{'totalPacks'}  += $totalPacks;
					$stats{'openMedic'}->{'byGroups'}->{$anatomicMainGroup}->{$year}->{'refundBasis'} += $refundBasis;
					$stats{'openMedic'}->{'byGroupsAndChemicalSubstance'}->{$anatomicMainGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'totalLines'}++;
					$stats{'openMedic'}->{'byGroupsAndChemicalSubstance'}->{$anatomicMainGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'totalPacks'}  += $totalPacks;
					$stats{'openMedic'}->{'byGroupsAndChemicalSubstance'}->{$anatomicMainGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'refundBasis'} += $refundBasis;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$year}->{'totalLines'}++;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$year}->{'totalPacks'}  += $totalPacks;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$year}->{'refundBasis'} += $refundBasis;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroupAndChemicalSubstanceSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'totalLines'}++;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroupAndChemicalSubstanceSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'totalPacks'}  += $totalPacks;
					$stats{'openMedic'}->{'byGroupsAndTherapeuticalSubGroupAndChemicalSubstanceSubGroup'}->{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$chemicalSubstanceSubGroup}->{$year}->{'refundBasis'} += $refundBasis;
					# die;
				}
			}
			$cpt++;
			if ($cpt == 100) {
				$cpt = 0;
				STDOUT->printflush("\rParsing [$year] data - Read [$lNum] lines        ");
			}
		}
		close $in;
		say "";
		$lNum--;
		$stats{'openMedic'}->{'byYears'}->{$year}->{'totalLines'} = $lNum;
	}
	p$stats{'openMedic'}->{'byGroups'};

	# p%ages;

	# Printing statistics.
	open my $out, '>:utf8', 'stats/openmedic_stats.json';
	print $out encode_json\%stats;
	close $out;

	# Printing categories.
	open $out, '>:utf8', 'public/doc/openmedic/openmedic_categories.csv';
	say $out "Goupe Principal Anatomique (l_atc1);Sous-Groupe Therapeutique (l_atc2);Sous-Groupe Pharmacologique (l_atc3);Sous-Groupe Chimique (l_atc4);Sous-Groupe Substance Chimique (l_atc5);Prescriptions Totales;Selection;";
	for my $anatomicMainGroup (sort keys %cats) {
		for my $therapeuticalSubGroup (sort keys %{$cats{$anatomicMainGroup}}) {
			for my $pharmaceuticalSubGroup (sort keys %{$cats{$anatomicMainGroup}->{$therapeuticalSubGroup}}) {
				for my $chemicalSubGroup (sort keys %{$cats{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$pharmaceuticalSubGroup}}) {
					for my $chemicalSubstanceSubGroup (sort keys %{$cats{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$pharmaceuticalSubGroup}->{$chemicalSubGroup}}) {
						my $totalPrescriptions = $cats{$anatomicMainGroup}->{$therapeuticalSubGroup}->{$pharmaceuticalSubGroup}->{$chemicalSubGroup}->{$chemicalSubstanceSubGroup} // die;
						my $selected = 'Non';
						if (exists $drugs{$chemicalSubstanceSubGroup}->{'chemicalSubGroup'}) {
							$selected = 'Oui';
						}
						say $out "$anatomicMainGroup;$therapeuticalSubGroup;$pharmaceuticalSubGroup;$chemicalSubGroup;$chemicalSubstanceSubGroup;$totalPrescriptions;$selected;";
					}
				}
			}
		}
	}
	close $out;
}

sub age_to_age_group {
	my ($age) = @_;
	return unless looks_like_number $age;
	my $ageGroup;
	if ($age eq '0') {
		$ageGroup = '0 - 19 ans';
	} elsif ($age eq '20') {
		$ageGroup = '20 - 59 ans';
	} elsif ($age eq '60') {
		$ageGroup = '60 ans et +';
	} elsif ($age eq '99') {
		$ageGroup = 'Age inconnu';
	} else {
		die "age : [$age]";
	}
	return $ageGroup;
}