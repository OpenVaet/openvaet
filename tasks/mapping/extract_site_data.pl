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
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::stat;
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use Math::Round qw(nearest);

# Original site file of the patients is here, page 2 to 41.
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-111721/5.2-listing-of-clinical-sites-and-cvs-pages-1-41.pdf&currentLanguage=en

# This script parses this file, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $randomizationPdfFile   = "public/pfizer_documents/native_files/pd-production-111721/5.2-listing-of-clinical-sites-and-cvs-pages-1-41.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $randomizationPdfFile;
my $randomizationPdfFolder = "raw_data/pfizer_trials/trial_sites";
my $outputFolder           = "raw_data/pfizer_trials/trial_sites_output";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $randomizationPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$randomizationPdfFile\" \"$randomizationPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

extract_data();

sub verify_pdf_structure {
	for my $htmlFile (glob "$randomizationPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 41) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_data {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$randomizationPdfFolder/page$pageNum.html";
		say "htmlFile : $htmlFile";
		my $content;
		open my $in, '<:utf8', $htmlFile;
		while (<$in>) {
			$content .= $_;
		}
		close $in;
		die unless $content;
		my $tree = HTML::Tree->new();
		$tree->parse($content);
		my $body = $tree->find('body');
		my @divs = $body->find('div');
		my $dNum = 0;
		for my $div (@divs) {
			my $text = $div->as_trimmed_text;
			$dNum++;
			say "$dNum | $text";
		}
	}
}