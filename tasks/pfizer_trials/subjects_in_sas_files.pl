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

my %subjects   = ();
for my $file (glob "raw_data/pfizer_trials/xpt_files_to_csv/*") {
	# This doesn't contain subjects data.
	next if $file eq 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0593482-0593595-125742_S1_M5_bnt162-01-S-D-pe.csv';
	next if $file eq 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0593327-0593481-125742_S1_M5_bnt162-01-S-D-ce.csv';
	say "Parsing [$file]";
	open my $in, '<:utf8', $file;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
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
			my $uSubjectId  = $values{'USUBJID'} // next;
			next unless $uSubjectId;
			next if $uSubjectId =~ /BNT162-/;
			my $subjectId   = $values{'SUBJID'};
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
	$subjects{'files'}->{$file}->{'totalRows'} = $totalRows;
	$subjects{'files'}->{$file}->{'totalSubjects'} = $totalPatientsInFile;
	say "totalRows           : $totalRows";
	say "totalPatientsInFile : $totalPatientsInFile";
	say "totalSubjects       : " . keys %{$subjects{'subjects'}};
}

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_sas_data_patients.json";
print $out encode_json\%subjects;
close $out;

# Prints SAS files summary.
open my $out2, '>:utf8', "$outputFolder/pfizer_sas_files_subjects.csv";
say $out2 "File;Total Rows;Total Subjects;";
for my $file (sort keys %{$subjects{'files'}}) {
	my $totalRows = $subjects{'files'}->{$file}->{'totalRows'} // die;
	my $totalSubjects = $subjects{'files'}->{$file}->{'totalSubjects'} // die;
	say $out2 "$file;$totalRows;$totalSubjects;";
}
close $out2;