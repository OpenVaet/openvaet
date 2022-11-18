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
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use Math::Round qw(nearest);
use Archive::Any;
use Digest::MD5  qw(md5 md5_hex md5_base64);

# Verifies we have the folder aiming at receiving the files.
make_path("public/pfizer_documents/zip_files")         unless (-d "public/pfizer_documents/zip_files");
make_path("public/pfizer_documents/json_words")        unless (-d "public/pfizer_documents/json_words");
make_path("public/pfizer_documents/pdf_to_html_files") unless (-d "public/pfizer_documents/pdf_to_html_files");

my %data = ();

# Gets the Pfizer docs.
get_pfizer_documents();

# Extracts the Pfizer docs.
extract_pfizer_documents();

my ($continue, $tries, $forward) = (0, 0, 0);
while ($continue == 0) {
	say "Done extracting Pfizer Files. Do you also wish to proceed with Pfizearch configuration ? (You must have xpdf installed as described in this page [https://openvaet.org/pfizearch/documentation?currentLanguage=en])";
	say "Enter [Y/n] to continue or exit";
	my $stdin = <STDIN>;
	chomp $stdin;
	$stdin = lc $stdin;
	if ($stdin) {
		if ($stdin eq 'y' || $stdin eq 'n') {
			$continue = 1;
			$forward  = 1 if $stdin eq 'y';
		}
	}
	if ($tries > 5) {
		say "Too many failed attempts. Exiting. Read the documentation & restart the script to proceed forward.";
		exit;
	}
}

exit unless $forward;


# Converts the Pfizer's PDFs to HTML.
# You'll need the XPDF version corresponding to your OS.
# Both files below are coming from https://www.xpdfreader.com/download.html
# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
# located in the bin32/64 subfolder of the archive you downloaded,
# in your project repository.
my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
convert_pdf_to_html();

# Outputs files preparation synthesis.
my %dump = %data;
delete $dump{'archives'}; # Comment this line if you wish a complete file structure dump.
open my $out, '>:utf8', 'stats/pfizer_documents_stats.json';
print $out encode_json\%dump;
close $out;

# We then index every word in every html file.
my $excludeAlphaNumeric = 0; # Either 0 or 1.
index_html_content();

sub get_pfizer_documents {

	# UA used to scrap target.
	my $cookie = HTTP::Cookies->new();
	my $ua     = LWP::UserAgent->new
	(
	    timeout    => 30,
	    cookie_jar => $cookie,
	    agent      => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
	);

	# Root url where we can find the PfizDocs.
	my $docsUrl         = 'https://phmpt.org/multiple-file-downloads/';
	say "Getting index on   [$docsUrl]";
	my $res = $ua->get($docsUrl);
	unless ($res->is_success)
	{
		die "failed to get [$docsUrl]";
	}
	my $content = $res->decoded_content;
	my $tree    = HTML::Tree->new();
	$tree->parse($content);
	my $docs    = $tree->find('tbody');
	my @docs    = $docs->find('tr');
	for my $docData (@docs) {
		my @tds = $docData->find('td');
		die unless scalar @tds == 4;
		my $fileName  = $tds[0]->as_trimmed_text // die;
		my $fileDate  = $tds[1]->as_trimmed_text // die;
		my $fileSize  = $tds[2]->as_trimmed_text // die;
		my $fileUrl   = $tds[3]->find('a')->attr_get_i('href') // die;
		my $fileLocal = "public/pfizer_documents/zip_files/$fileName";
		say "Getting document   [$fileName] - $fileSize";
	    unless (-f $fileLocal) {
	        my $rc = getstore($fileUrl, $fileLocal);
	        if (is_error($rc)) {
	            die "getstore of <$fileUrl> failed with $rc";
	        }
	    }
	    my %archive = ();
	    $archive{'fileName'}  = $fileName;
	    $archive{'fileDate'}  = $fileDate;
	    $archive{'fileSize'}  = $fileSize;
	    $archive{'fileLocal'} = $fileLocal;
	    $archive{'fileUrl'}   = $fileUrl;
	    push @{$data{'archives'}}, \%archive;
	}
}

sub extract_pfizer_documents {
	my %tmp = %data;
	%data = ();
	for my $archive (@{$tmp{'archives'}}) {
		my %archive   = %$archive;
		my $fileLocal = %$archive{'fileLocal'} // die;
		my $fileName  = %$archive{'fileName'}  // die;
		$fileName     =~ s/\.zip$//;
		my $unzipFolder = "public/pfizer_documents/native_files/$fileName";
		make_path($unzipFolder) unless (-d $unzipFolder);
		my $archive   = Archive::Any->new($fileLocal);
		if (not $archive) {
		    say 'Not unzipped';
		    exit;
		}
		if ($archive->is_naughty) {
		    die 'Naughty .zip found : ' . $fileLocal;
		}
		my $shouldUnzip = 0;
		for my $file ($archive->files) {
			my $unzipFile = "$unzipFolder/$file";
			my @elems     = split '\.', $unzipFile;
			my $fileExt   = $elems[scalar@elems-1];
			$data{'extensions'}->{$fileExt}->{'totalFiles'}++;
			my $filePath  = "$fileName/$file";

			# We will output the PDF in a folder corresponding to the MD5 of
			# the archive name & the file name concatenated.
			my $fileMd5;
			$fileMd5 = md5_hex($filePath);
			unless (-f $unzipFile) {
				$shouldUnzip = 1;
			}
			if ($fileExt eq 'pdf') {
				my $htmlFolder = 'public/pfizer_documents/pdf_to_html_files/' . $fileMd5;
			    $archive{'files'}->{$file}->{'htmlFolder'} = $htmlFolder;
			}
		    $archive{'files'}->{$file}->{'filePath'}  = $filePath;
		    $archive{'files'}->{$file}->{'fileMd5'}   = $fileMd5;
		    $archive{'files'}->{$file}->{'fileExt'}   = $fileExt;
		    $archive{'files'}->{$file}->{'fileLocal'} = $unzipFile;
		}
		if ($shouldUnzip) {
			$archive->extract($unzipFolder);
		}
		$archive{'unzipFolder'} = $unzipFolder;

	    # Gets file size once extracted.
	    for my $file (sort keys %{$archive{'files'}}) {
	    	my $fileLocal = $archive{'files'}->{$file}->{'fileLocal'} // die;
	    	die "failed to find expected file" unless -f $fileLocal;
			my $fileStats = stat($fileLocal);
			$archive{'files'}->{$file}->{'fileSize'} = nearest(0.1, $fileStats->size / 1000000) . ' MB';
	    }
	    push @{$data{'archives'}}, \%archive;
	}
}

sub convert_pdf_to_html {
	STDOUT->printflush("\rParsing pdf files  [initiating ...]");
	my %tmp = %data;
	$data{'archives'} = ();

	# Counts the files which will have to be processed at this step.
	my ($parsedCurrent, $parsedTotal)       = (0, 0);
	my ($extractedCurrent, $extractedTotal) = (0, 0);
	for my $archive (@{$tmp{'archives'}}) {
		for my $fileName (sort keys %{%$archive{'files'}}) {
			my $fileExt = %$archive{'files'}->{$fileName}->{'fileExt'} // die;
			if ($fileExt eq 'pdf') {
				my $filePath   = %$archive{'files'}->{$fileName}->{'filePath'}   // die;
				my $fileMd5    = %$archive{'files'}->{$fileName}->{'fileMd5'}    // die;
				my $htmlFolder = %$archive{'files'}->{$fileName}->{'htmlFolder'} // die;

				# We verify if it exists, and if so, if we indeed have extracted files.
				my $requiresExtract = 1;
				if (-d $htmlFolder) {
					for my $htmlFile (glob "$htmlFolder/*") {
						$requiresExtract = 0;
					}
				}

				# Overwise, we set it to be extracted.
				if ($requiresExtract) {
					$extractedTotal++;
				}
			}
			$parsedTotal++;
		}
	}

	# Processing PDF extracts to HTML format.
	for my $archive (@{$tmp{'archives'}}) {
		my %archive = %$archive;
		$archive{'files'} = (); # We reformat the files for a more pleasant output.
		for my $fileName (sort keys %{%$archive{'files'}}) {
			my $fileExt       = %$archive{'files'}->{$fileName}->{'fileExt'}   // die;
			my $filePath      = %$archive{'files'}->{$fileName}->{'filePath'}  // die;
			my $fileMd5       = %$archive{'files'}->{$fileName}->{'fileMd5'}   // die;
			my $fileLocal     = %$archive{'files'}->{$fileName}->{'fileLocal'} // die;
			my $htmlFolder    = %$archive{'files'}->{$fileName}->{'htmlFolder'};
			my %file          = %{%$archive{'files'}->{$fileName}};
			$file{'fileName'} = $fileName;
			$parsedCurrent++;
			if ($fileExt eq 'pdf') {
				die unless $htmlFolder;
				my $requiresExtract = 1;
				if (-d $htmlFolder) {
					for my $htmlFile (glob "$htmlFolder/*") {
						$requiresExtract = 0;
					}
				}
				if ($requiresExtract) {
					$extractedCurrent++;
					my $pdfToHtmlCommand = "$pdfToHtmlExecutable \"$fileLocal\" \"$htmlFolder\"";
					system($pdfToHtmlCommand);
				}

				# Verifies that we have properly extracted the PDF, and counts the number of HTML pages generated.
				my $totalPages = 0;
				for my $pdfExtractFile (glob "$htmlFolder/*") {
					my $fileName = $pdfExtractFile;
					my @elems = split '\/', $fileName;
					$fileName = $elems[scalar@elems - 1];
					my @extElems = split '\.', $fileName;
					my $fileExt  = $extElems[scalar@extElems - 1];
					if ($fileExt eq 'html') {

						# We erase the index generated by pdftohtml.
						if ($fileName eq 'index.html') {
							unlink $pdfExtractFile;
						} else {
							my ($pageNum) = $fileName =~ /page(.*)\.html/;
							die unless $pageNum && looks_like_number $pageNum;
							my $fileStats = stat($pdfExtractFile);
							my %htmlFile  = ();
							$htmlFile{'fileLocal'} = $pdfExtractFile;
							$htmlFile{'fileName'}  = $fileName;
							$htmlFile{'filePath'}  = $filePath . ", page $pageNum";
							$htmlFile{'fileExt'}   = $fileExt;
							$htmlFile{'fileSize'}  = nearest(0.1, $fileStats->size / 1000) . ' KB';
							push @{$file{'files'}}, \%htmlFile;
							$data{'extensions'}->{'pdf'}->{'html'}->{'totalFiles'}++;
							# say "pdfExtractFile : $pdfExtractFile";
							$totalPages++;
						}
					} else {

						# We erase fonts & png files, which we won't use for indexing purposes.
						if ($fileExt ne 'png') {
							unlink $pdfExtractFile;
						}
					}
				}
				$file{'totalPages'} = $totalPages;
			}
			push @{$archive{'files'}}, \%file;
			STDOUT->printflush("\rParsing pdf files  [$parsedCurrent / $parsedTotal] - extracted [$extractedCurrent / $extractedTotal]");
		}
	    push @{$data{'archives'}}, \%archive;
	}

	say "" if $parsedTotal;
}

sub index_html_content {

	my %jsonData         = ();

	# Prepares the excluded keywords.
	my %excludedKeywords = ();
	my @excludedKeywords = ("i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your", "yours", "yourself", "yourselves", "he", "him", "his", "himself", "she", "her", "hers", "herself", "it", "its", "itself", "they", "them", "their", "theirs", "themselves", "what", "which", "who", "whom", "this", "that", "these", "those", "am", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "having", "do", "does", "did", "doing", "a", "an", "the", "and", "but", "if", "or", "because", "as", "until", "while", "of", "at", "by", "for", "with", "about", "against", "between", "into", "through", "during", "before", "after", "above", "below", "to", "from", "up", "down", "in", "out", "on", "off", "over", "under", "again", "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "any", "both", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than", "too", "very", "s", "t", "can", "will", "just", "don", "should", "now");
	for my $k (@excludedKeywords) {
		$excludedKeywords{$k} = 1;
	}
	my ($current, $total) = (0, 0);
	for my $archive (@{$data{'archives'}}) {
		for my $pdfFile (@{%$archive{'files'}}) {
			my $fileExt   = %$pdfFile{'fileExt'} // die;
			if ($fileExt eq 'pdf') {
				for my $htmlFile (@{%$pdfFile{'files'}}) {
					$total++;
				}
			}
		}
	}

	# Extracts the text from the HTML files, and notes the keywords of interest.
	my $fileRef = 0;
	for my $archive (@{$data{'archives'}}) {
		for my $pdfFile (@{%$archive{'files'}}) {
			my $fileExt = %$pdfFile{'fileExt'} // die;
			if ($fileExt eq 'pdf') {
				my $pdfFileLocal = %$pdfFile{'fileLocal'}  // die;
				$pdfFileLocal    =~ s/public\///;
				my $fileSize     = %$pdfFile{'fileSize'}   // die;
				my $fileMd5      = %$pdfFile{'fileMd5'}    // die;
				my $totalPages   = %$pdfFile{'totalPages'} // die;
				my $fileShort    = $pdfFileLocal;
                $fileShort       =~ s/pfizer_documents\/native_files\///;
				my %pdfObj = ();
				$pdfObj{'fileMd5'}    = $fileMd5;
				$pdfObj{'fileSize'}   = $fileSize;
				$pdfObj{'fileShort'}  = $fileShort;
				$pdfObj{'fileLocal'}  = $pdfFileLocal;
				$pdfObj{'totalPages'} = $totalPages;
				push @{$jsonData{'files'}}, \%pdfObj;
				my %fileWords    = ();
				for my $htmlFile (@{%$pdfFile{'files'}}) {
					$current++;
					STDOUT->printflush("\rParsing html files [$current / $total]");
					my $htmlFileLocal = %$htmlFile{'fileLocal'} // die;
        			my ($pageNum) = $htmlFileLocal =~ /\/page(.*)\.html$/;
					# say "htmlFileLocal : $htmlFileLocal";
					open my $in, '<:utf8', $htmlFileLocal;
					my $content;
					while (<$in>) {
						$content .= $_;
					}
					close $in;
					my $tree = HTML::Tree->new();
					$tree->parse($content);
					my @divs = $tree->find('div');
					for my $div (@divs) {
						my $line = lc $div->as_trimmed_text;
						my @words = split '[\{\}\*\[\]=\'\"\(\)_\-\\\\/,;.:+#!? ]', $line;
						for my $word (@words) {
							next unless $word;

							# Here we proceed to the filtering of alphanumerical keywords,
							# common terms, and other pollutions in most search scenarios,
							# which we will use only if a search fails to find
							# results in the "fast" query attempt.
							next unless length $word >= 3;
							# next if looks_like_number $word;
							# next if $word =~ /[a-zA-Z0-9]*[0-9]+[a-zA-Z]+/;
							# next if $word =~ /[a-zA-Z0-9]*[0-9]+/;
							next if exists $excludedKeywords{$word};
							$jsonData{'words'}->{$word}->{$fileRef}++;
							$fileWords{$word}->{$pageNum}++;
						}
					}
				}
				$fileRef++;
				my $wordFile = "public/pfizer_documents/json_words/$fileMd5.json";
				unless (-f $wordFile) {
					open my $out, '>:utf8', $wordFile;
					print $out encode_json\%fileWords;
					close $out;
				}
			}
		}
	}

	# Outputs data optimized for search.
	open my $out, '>:utf8', 'stats/pfizer_json_data.json';
	print $out encode_json\%jsonData;
	close $out;
}