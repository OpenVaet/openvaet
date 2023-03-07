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
use Encode;
use HTML::Tree;
use Encode::Unicode;
use Math::Round qw(nearest);
use Text::CSV qw( csv );
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);

my $pregnanciesFile = 'dailyclout_paper/pregnancies.csv';
my $pdfDataFile     = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';
my $xptDataFile     = 'public/doc/pfizer_trials/pfizer_sas_data_patients.json';
my $pdfToMd5File    = 'stats/pfizer_json_data.json';
my $xptSynthFile    = 'public/doc/pfizer_trials/xpt_to_csv_conversion.csv';

my %xptData         = ();
my %pdfData         = ();
my %md5Data         = ();
my %xptSynthesis    = ();

load_md5_data();
load_xpt_data();
load_pdf_data();
load_xpt_synthesis();
my %xptFiles    = ();
my %pdfFiles    = ();
my %pregnancies = ();
load_pregnancies_data();

parse_xpt_files();
parse_pdf_files();

open my $out, '>:utf8', 'public/doc/pfizer_trials/pregnancies_report.json';
print $out encode_json\%pregnancies;
close $out;

sub load_md5_data {
	open my $in, '<:utf8', $pdfToMd5File;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	for my $fileData (@{%$json{'files'}}) {
		my $fileLocal = %$fileData{'fileLocal'} // die;
		my $fileMd5 = %$fileData{'fileMd5'} // die;
		my $fileShort = %$fileData{'fileShort'} // die;
		$md5Data{$fileLocal}->{'fileMd5'}   = $fileMd5;
		$md5Data{$fileLocal}->{'fileShort'} = $fileShort;
	}
	# p%md5Data;
	# die;
}
# p%xptFiles;

sub load_xpt_data {
	open my $in, '<:utf8', $xptDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%xptData = %$json;
}

sub load_pdf_data {
	open my $in, '<:utf8', $pdfDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfData = %$json;
}

sub load_xpt_synthesis {
	open my $in, '<:utf8', $xptSynthFile;
	while (<$in>) {
		chomp $_;
		my ($localCsvFile, $localXptFile) = split ';', $_;
		my ($xptFile) = $localXptFile;
		$xptFile =~ s/public\/pfizer_documents\/native_files\///g;
		$xptSynthesis{$localCsvFile} = $xptFile;
		# say $_;
		# die;
	}
	# p%xptSynthesis;
	# die;
	close $in;
}

sub load_pregnancies_data {
	open my $in, '<:utf8', $pregnanciesFile;
	while (<$in>) {
		chomp $_;
		my @elems = split ' ', $_;
		my $subjectId = $elems[0];
		die unless $subjectId;
		my $totalXptFiles = keys %{$xptData{'subjects'}->{$subjectId}->{'files'}};
		my $totalPdfFiles = keys %{$pdfData{'subjects'}->{$subjectId}->{'files'}};
		# unless ($totalXptFiles && $totalPdfFiles) {
			# say "subjectId     : [$subjectId]";
			# say "totalXptFiles : [$totalXptFiles]";
			# say "totalPdfFiles : [$totalPdfFiles]";
			# p$xptData{'subjects'}->{$subjectId}->{'files'};
			# p$pdfData{'subjects'}->{$subjectId}->{'files'};
			# die;
		# }
		die unless exists $xptData{'subjects'}->{$subjectId}->{'files'};
		die unless exists $pdfData{'subjects'}->{$subjectId}->{'files'};
		for my $xptFile (sort keys %{$xptData{'subjects'}->{$subjectId}->{'files'}}) {
			$xptFiles{$xptFile} = 1;
			my $xptShort = $xptSynthesis{$xptFile} // die;
			$pregnancies{$subjectId}->{'xpt'}->{$xptShort}->{'appears'} = 1;
		}
		for my $pdfFile (sort keys %{$pdfData{'subjects'}->{$subjectId}->{'files'}}) {
			my $fileShort = $md5Data{$pdfFile}->{'fileShort'} // die;
			my $fileMd5 = $md5Data{$pdfFile}->{'fileMd5'} // die;
			$pdfFiles{$pdfFile} = 1;
			$pregnancies{$subjectId}->{'pdf'}->{$fileShort}->{'fileMd5'} = $fileMd5;
		}
		# die;
	}
	close $in;
}

sub parse_xpt_files {
	my ($total, $current) = (0, 0);
	$total = keys %xptFiles;
	for my $xptFile (sort keys %xptFiles) {
		$current++;
		STDOUT->printflush("\rParsing XPT Files [$current / $total]");
		parse_xpt_file($xptFile);
	}
	say "";
}

sub parse_xpt_file {
	my $xptFile    = shift;
	my $xptShort   = $xptSynthesis{$xptFile} // die;
	open my $in, '<:utf8', $xptFile;
	my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	my %subjects   = ();
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
			my $subjectId;
			if ($values{'SUBJID'}) {
				$subjectId     = $values{'SUBJID'}  // die;
			} else {
				my $uSubjectId = $values{'USUBJID'} // die;
				($subjectId)   = $uSubjectId =~ /^C4591001 .... (.*)$/;
				unless ($subjectId && $subjectId =~ /^........$/) {
					next;
				}
			}
			die unless $subjectId;
			if (exists $pregnancies{$subjectId}) {
				unless (exists $pregnancies{$subjectId}->{'xpt'}->{$xptShort}->{'columns'}) {
					for my $columnNum (sort{$a <=> $b} keys %dataLabels) {
						my $column = $dataLabels{$columnNum} // die;
						push @{$pregnancies{$subjectId}->{'xpt'}->{$xptShort}->{'columns'}}, $column;
					}
				}
				for my $columnNum (sort{$a <=> $b} keys %dataLabels) {
					my $column = $dataLabels{$columnNum} // die;
					my $value = $values{$column};
					push @{$pregnancies{$subjectId}->{'xpt'}->{$xptShort}->{'rows'}->{$dRNum}}, $value;
				}
			}
			# p$pregnancies{$subjectId}->{'xpt'}->{$xptFile};die;
		}
	}
	close $in;
}

sub parse_pdf_files {
	my ($total, $current) = (0, 0);
	$total = keys %pdfFiles;
	for my $pdfFile (sort keys %pdfFiles) {
		$current++;
		STDOUT->printflush("\rParsing PDF Files [$current / $total]");
		parse_pdf_file($pdfFile);
	}
	say "";
}

sub parse_pdf_file {
	my $pdfFile   = shift;
	my $md5Path   = $md5Data{$pdfFile}->{'fileMd5'}   // die;
	my $fileShort = $md5Data{$pdfFile}->{'fileShort'} // die;
	for my $pageFile (glob "public/pfizer_documents/pdf_to_html_files/$md5Path/*.html") {
		my ($pageNum) = $pageFile =~ /public\/pfizer_documents\/pdf_to_html_files\/$md5Path\/page(.*)\.html/;
		parse_pdf_page($fileShort, $pageNum, $pageFile);
	}
}

sub parse_pdf_page {
	my ($fileShort, $pageNum, $pageFile) = @_;
	# say "";
	# say "fileShort : $fileShort";
	# say "pageFile  : $pageFile";
	# say "pageNum   : [$pageNum]";
	open my $in, '<:utf8', $pageFile;
	my $html;
	while (<$in>) {
		$html .= $_;
	}
	my $tree = HTML::Tree->new();
	$tree->parse($html);
	my $body = $tree->find('body');
	my @divs = $body->find('div');
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		my @elems = split ' ', $text;
		for my $elem (@elems) {
			for my $subjectId (sort keys %pregnancies) {
				if ($elem =~ /$subjectId/) {
					$pregnancies{$subjectId}->{'pdf'}->{$fileShort}->{'pages'}->{$pageNum} = 1;
				}
			}
		}
	}
	close $in;
}

