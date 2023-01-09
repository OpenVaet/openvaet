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
use String::Similarity;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

# Fetching XPT files details provided.
my $dataCsv        = Text::CSV_XS->new ({ binary => 1 });
my $xptDetailsFile = 'tasks/pfizer_trials/abstractor_xpt_documentation_202301080000.csv';
my %xptDetails     = ();
my %subjects       = ();
my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder)
	unless (-d $outputFolder);

# Loads XPT files definitions.
load_xpt_details();

# Parse XPT files looking for C4591001's subjects. 
parse_xpt_files();

# Prints subjects JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_sas_data_patients.json";
print $out encode_json\%subjects;
close $out;

# Prints SAS files summary.
open my $out2, '>:utf8', "$outputFolder/pfizer_sas_files_subjects.csv";
say $out2 "File;Total Rows;Total Subjects;Description;CDISC Description;";
for my $file (sort keys %{$subjects{'files'}}) {
	my $totalRows            = $subjects{'files'}->{$file}->{'totalRows'}            // die;
	my $totalSubjects        = $subjects{'files'}->{$file}->{'totalSubjects'}        // die;
	my $fileCDiscDescription = $subjects{'files'}->{$file}->{'fileCDiscDescription'} // die;
	my $fileDescription      = $subjects{'files'}->{$file}->{'fileDescription'}      // die;
	say $out2 "$file;$totalRows;$totalSubjects;$fileDescription;$fileCDiscDescription;";
}
close $out2;

sub load_xpt_details {
	open my $in, '<:utf8', $xptDetailsFile;
	my %dataLabels = ();
	my ($totalRows,
		$expectedValues) = (0, 0);
	while (<$in>) {
		chomp $_;
		$totalRows++;

		# Fixing misformats.
		$_ =~ s/ – / - /g;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($totalRows == 1) {
			my @labels = split ',', $line;
			my $lN     = 0;
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
			my %values    = ();
			for my $value (@row) {
				my $label = $dataLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			my $rxpttable     = $values{'rxpttable'}     // die;
			my $datasetprefix = $values{'datasetprefix'} // die;
			my $file          = $rxpttable . "_$datasetprefix";
			while ($file =~ /__/) {
				$file =~ s/__/_/g;
			}
			for my $label (sort keys %values) {
				my $value = $values{$label} // die;
				$xptDetails{$file}->{$label} = $value;
			}
		}
	}
	close $in;
}

sub parse_xpt_files {
	my %filesAttributed = ();
	for my $file (glob "raw_data/pfizer_trials/xpt_files_to_csv/*") {
		# This doesn't contain subjects data.
		next if $file eq 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0593482-0593595-125742_S1_M5_bnt162-01-S-D-pe.csv';
		next if $file eq 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0593327-0593481-125742_S1_M5_bnt162-01-S-D-ce.csv';
		my $fileConverted = $file;
		$fileConverted    =~ s/-/_/g;
		($fileConverted)  = $fileConverted =~ /xpt_files_to_csv\/(.*)\.csv/;
		say "Parsing [$file]";
		my %sims = ();
		for my $f (sort keys %xptDetails) {
			my $sim = similarity($f, $file);
			$sims{$sim}->{$f} = 1;
		}
		my ($similarity, $fileMatching);
		for my $sim (sort{$b <=> $a} keys %sims) {
			die if keys %{$sims{$sim}} > 1;
			say "sim : $sim";
			$similarity = $sim;
			for my $f (sort keys %{$sims{$sim}}) {
				$fileMatching = $f;
			}
			last;
		}
		die if exists $filesAttributed{$fileMatching};
		$filesAttributed{$fileMatching} = 1;
		my $fileDescription      = $xptDetails{$fileMatching}->{'genericdescription'} // 'NA';
		my $fileCDiscDescription = $xptDetails{$fileMatching}->{'cdiscdescription'}   // 'NA';
		open my $in, '<:utf8', $file;
		my %dataLabels = ();
		my ($totalRows,
			$expectedValues) = (0, 0);
		my $totalPatientsInFile = 0;
		while (<$in>) {
			$totalRows++;

			# Fixing misformats.
			$_ =~ s/ – / - /g;

			# Verifying line.
			my $line = $_;
			$line = decode("ascii", $line);
			for (/[^\n -~]/g) {
			    printf "Bad character: %02x\n", ord $_;
			    die;
			}

			# First row = line labels.
			if ($totalRows == 1) {
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
				my $uSubjectId   = $values{'USUBJID'} // next;
				next unless $uSubjectId;
				next if $uSubjectId =~ /BNT162-/;
				my $subjectId    = $values{'SUBJID'};
				unless ($subjectId) {
					($subjectId) = $uSubjectId =~ /^C\d\d\d\d\d\d\d \d\d\d\d (\d\d\d\d\d\d\d\d)/;
					die "uSubjectId : $uSubjectId" unless $subjectId;
				}
				$subjects{'subjects'}->{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
				$subjects{'subjects'}->{$subjectId}->{'uSubjectId'} = $uSubjectId;
				unless (exists $subjects{'subjects'}->{$subjectId}->{'files'}->{$file}) {
					$totalPatientsInFile++;				
				}
				$subjects{'subjects'}->{$subjectId}->{'files'}->{$file}->{'totalRows'}++;
				# p$subjects{$uSubjectId};
				# p%values;
				# p%subjects;
				# die;
				# last if $totalRows > 100;
				# say "uSubjectId : $uSubjectId";
				# say "isDtc      : $isDtc";
				# die;
				# die;
			}
		}
		close $in;
		$totalRows--;
		$subjects{'files'}->{$file}->{'totalRows'}            = $totalRows;
		$subjects{'files'}->{$file}->{'fileDescription'}      = $fileDescription;
		$subjects{'files'}->{$file}->{'fileCDiscDescription'} = $fileCDiscDescription;
		$subjects{'files'}->{$file}->{'totalSubjects'}        = $totalPatientsInFile;
		say "totalRows           : $totalRows";
		say "totalPatientsInFile : $totalPatientsInFile";
		say "totalSubjects       : " . keys %{$subjects{'subjects'}};
	}
}