#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");
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
use Encode;
use HTML::Entities;

# This script fetches the original PDF, converts it to HTML,
# and parses the targeted tables content to restitute a usable .CSV 
my $pdfFile       = "tasks/pfizer_trials/amyloidosis/125742_S7_M5_5351_bnt162-01-interim3-reports.pdf";
die "Missing source file, verify that [tasks/pfizer_trials/amyloidosis/125742_S7_M5_5351_bnt162-01-interim3-reports.pdf] is present first." unless -f $pdfFile;
my $htmlFolder    = "tasks/pfizer_trials/amyloidosis/html";
my $outputFolder  = "tasks/pfizer_trials/amyloidosis";
my $expectedPages = 524;
my %path          = ();
my $nomF          = 'tasks/pfizer_trials/amyloidosis/nomenclature.csv';
my $url           = "http://163.172.57.240:5503/aws";
my $tot           = 0;
my %rawData       = ();
my %data          = ();
load_nomenclature();

# If the pdf hasn't been extracted already, proceeding.
unless (-d $htmlFolder) {

	# Converts the PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$pdfFile\" \"$htmlFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();
extract_tables_data();

sub verify_pdf_structure {
	for my $htmlFile (glob "$htmlFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == $expectedPages) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub load_nomenclature {
	open my $in, '<:utf8', $nomF;
	my $formerLabel;
	while (<$in>) {
		chomp $_;
		my ($label, $cdRef, $start0235, $end0235, $start0241, $end0241) = split ';', $_;
		next if $start0235 eq '0235 start';
		if ($label) {
			$formerLabel = $label;
		}
		$tot++;
		$path{$formerLabel}->{$cdRef}->{'start0235'} = $start0235;
		$path{$formerLabel}->{$cdRef}->{'end0235'}   = $end0235;
		$path{$formerLabel}->{$cdRef}->{'start0241'} = $start0241;
		$path{$formerLabel}->{$cdRef}->{'end0241'}   = $end0241;
	}
	close $in;
}

sub extract_tables_data {
	my $cpt = 0;
	for my $label (sort keys %path) {
		for my $cdRef (sort keys %{$path{$label}}) {
			$cpt++;
			my $start0235 = $path{$label}->{$cdRef}->{'start0235'} // die;
			my $end0235   = $path{$label}->{$cdRef}->{'end0235'}   // die;
			my $start0241 = $path{$label}->{$cdRef}->{'start0241'} // die;
			my $end0241   = $path{$label}->{$cdRef}->{'end0241'}   // die;
			my %structure = ();
			for my $page ($start0235 .. $end0235) {
				say "Processing [$label - $cdRef] - [$page]";
				my $file  = "tasks/pfizer_trials/amyloidosis/raw/$page.png";
				die "File not found: $file" unless -f $file;
				my $htmlFile = "$htmlFolder/page$page.html";
				# say "htmlFile : $htmlFile";
				my $content;
				open my $in, '<:utf8', $htmlFile;
				while (<$in>) {
					$content .= $_;
				}
				close $in;
				die unless $content;
				my $html = decode_entities($content);
				my $tree = HTML::Tree->new();
				$tree->parse($html);
				my $body = $tree->find('body');
				my @divs = $body->find('div');
				my %structure = ();
				my ($dNum, $entryNum, $init, $end) = (0, 0, 0, 0);
				for my $div (@divs) {
					my $text = $div->as_trimmed_text;
					last if $text =~ /Note:/;
					$dNum++;
					# say "$dNum | $text";
					my $style = $div->attr_get_i('style');
					# say "style : $style";
					# die;
					my ($leftMargin, $topMargin) = $style =~ /left:(.*)px; top:(.*)px;/;
					die unless $leftMargin && $topMargin;
					$structure{$topMargin} += $leftMargin;
					my $totalLeft = $structure{$topMargin} // die;
					if ($text eq 'Cytokine') {
						$init = 1;
					}
					if ($text eq 'Strictly Confidential') {
						$end  = 1;
					}
					if ($init && !$end) {
						last if $text =~ /Page \d/;
						$entryNum++;
						# say "$leftMargin | $topMargin -> $totalLeft | $text";
						$topMargin = nearest(5, $topMargin);
			    		$rawData{$label}->{$cdRef}->{$page}->{$topMargin}->{$totalLeft} = $text;
					}
					# die;
				}
			}
			finalize_table($label, $cdRef);
		}
		# p%rawData;
		# die;
	}
}

sub finalize_table {
	my ($label, $cdRef) = @_;
	my $columnsExpected;
	if ($cdRef eq 'CD4') {
		$columnsExpected = 10;
	} elsif ($cdRef eq 'CD8') {
		$columnsExpected = 10;
	} else {
		die "columnsExpected : $columnsExpected";
	}
	my $outFile = 'tasks/pfizer_trials/amyloidosis/debug.txt';
	open(my $out, '>:encoding(utf8)', $outFile) or die "Could not open file '$outFile' $!";
	unless (exists $data{$label}->{$cdRef}->{'headers'}) {
		# Rows up to the first subject ID are the header.
		for my $page (sort{$a <=> $b} keys %{$rawData{$label}->{$cdRef}}) {
			my ($firstDataRowTop, $header2ndRowTop);
			for my $topMargin (sort{$a <=> $b} keys %{$rawData{$label}->{$cdRef}->{$page}}) {
				my $firstElem;
				# p$rawData{$label}->{$cdRef}->{$topMargin};
				# die;
				for my $leftMargin (sort{$a <=> $b} keys %{$rawData{$label}->{$cdRef}->{$page}->{$topMargin}}) {
					$firstElem = $rawData{$label}->{$cdRef}->{$page}->{$topMargin}->{$leftMargin} // die;
					say "firstElem : $firstElem";
					say $out "firstElem : $firstElem";
					say $out encode('utf8', $firstElem);
					# die;
					if ($firstElem eq 'Dose') {
						unless ($header2ndRowTop) {
							$header2ndRowTop = $topMargin;
						}
					}
					last;
				}
				if ($firstElem =~ /276-/) {
					unless ($firstDataRowTop) {
						$firstDataRowTop = $topMargin;
					}
				}
			}
			die unless $firstDataRowTop && $header2ndRowTop;
			say "firstDataRowTop : $firstDataRowTop";
			die;
			last;
		}
	}
	close $out;
	p$rawData{$label}->{$cdRef};
	say "columnsExpected : $columnsExpected";
	die;
}