package OpenVaet::Controller::Pfizearch;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Scalar::Util qw(looks_like_number);
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;
no autovivification;

sub index {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub documentation {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my %docData = ();

    open my $in, '<:utf8', 'stats/pfizer_documents_stats.json';
    my $fileTypes;
    while (<$in>) {
        $fileTypes .= $_;
    }
    close $in;
    $fileTypes = decode_json($fileTypes);
    %docData = %$fileTypes;
    for my $file (glob "public/pfizer_documents/zip_files/*") {
        my $archiveName = $file;
        $archiveName =~ s/public\/pfizer_documents\/zip_files\///;
        $docData{'archives'}->{$archiveName} = 1;
    }
    p%docData;

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        docData         => \%docData
    );
}

sub search {
    my $self            = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $terms           = lc $self->param('terms');
    my $allTermsOnly    = $self->param('allTermsOnly') // 'true';

    # Loggin session if unknown.
    session::session_from_self($self);
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading JSON data.
    my $pfizFile   = 'stats/pfizer_json_data.json';
    my $filesFound = 0;
    my @results    = ();
    my $totalTerms = 0;
    if (-f $pfizFile && $terms) {

        # Breaks down the incoming normalized request.
        my @terms = format_terms($terms);
        my %terms = ();
        for my $term (@terms) {
            next if length $term < 3;
            $totalTerms++;
            $terms{$term} = 1;
        }
    	my $json;
    	open my $in, '<:utf8', $pfizFile;
    	while (<$in>) {
    		$json .= $_;
    	}
    	close $in;
    	$json = decode_json($json);

        my @files = @{%$json{'files'}};

        # Identifying where the searched terms are appearing.
        my %pre_results = ();
        for my $word (keys %{%$json{'words'}}) {
            # if ($word =~ /term/) {
            if (exists $terms{$word}) {
                for my $fileRef (keys %{%$json{'words'}->{$word}}) {
                    my $wordOccurences = %$json{'words'}->{$word}->{$fileRef} // die;
                    $pre_results{$fileRef}->{$word} += $wordOccurences;
                }
            }
        }

        # Sorting results by occurences.
        my %results    = ();
        for my $fileRef (sort{$b <=> $a} keys %pre_results) {
            if ($allTermsOnly eq 'true' && $totalTerms > 1) {
                my %fileObj = %{$files[$fileRef]};
                my $fileMd5 = $fileObj{'fileMd5'} // die;
                next unless keys %{$pre_results{$fileRef}} == $totalTerms;
                my %pages = pages_from_file($fileMd5, $allTermsOnly, $totalTerms, @terms);
                next unless keys %pages;
            }
            $filesFound++;
            my $wordOccurences = 0;
            for my $word (sort keys %{$pre_results{$fileRef}}) {
                $wordOccurences += $pre_results{$fileRef}->{$word};
            }
            $results{$wordOccurences}->{$fileRef} = 1;
        }
        for my $wordOccurences (sort{$b <=> $a} keys %results) {
            for my $fileRef (sort keys %{$results{$wordOccurences}}) {
                my %fileObj = %{$files[$fileRef]};
                $fileObj{'wordOccurences'} = $wordOccurences;
                push @results, \%fileObj;
            }
        }
        # p%results;
    	# p$json;
    }

    $self->render(
        totalTerms      => $totalTerms,
        allTermsOnly    => $allTermsOnly,
        currentLanguage => $currentLanguage,
        terms           => $terms,
        filesFound      => $filesFound,
        languages       => \%languages,
        results         => \@results
    );
}

sub format_terms {
    my ($terms) = @_;
    my @terms;
    if ($terms) {
        @terms = split '[\{\}\*\[\]=\'\"\(\)_\-\\\\/,;.:+#!? ]', $terms;
    }
    return @terms;
}

sub pdf_search_details {
    my $self            = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $pNum            = $self->param('pNum')            // 1;
    my $allTermsOnly    = $self->param('allTermsOnly')    // 'false';
    my $fileShort       = $self->param('fileShort');
    my $terms           = $self->param('terms');
    my $fileLocal       = "pfizer_documents/native_files/" . $fileShort;
    my $fileMd5         = $self->param('fileMd5');
    unless ($fileMd5 || $fileLocal || $terms || $fileShort) {
        $self->render(text => 'Missing mandatory data');
    }
    say "fileLocal    : $fileLocal";
    say "allTermsOnly : $allTermsOnly";
    say "fileShort    : $fileShort";
    say "fileMd5      : $fileMd5";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Breaks down the incoming normalized request.
    my @terms = format_terms($terms);
    my $totalTerms = 0;
    for my $term (@terms) {
        next if length $term < 3;
        $totalTerms++;
    }

    my %results        = pages_from_file($fileMd5, $allTermsOnly, $totalTerms, @terms);
    my $totalPages     = keys %results;
    my ($pageNum, $content, $htmlFileLocal, $wordOccurences);
    my $p = 0;
    my ($formerPNum, $nextPNum);
    for my $pN (sort{$a <=> $b} keys %results) {
        $p++;
        if ($p == $pNum) {
            $pageNum        = $pN;
            $content        = $results{$pN}->{'content'}        // die;
            $htmlFileLocal  = $results{$pN}->{'htmlFileLocal'}  // die;
            $wordOccurences = $results{$pN}->{'wordOccurences'} // die;
        } else {
            if ($pageNum) {
                $nextPNum   = $p;
                last;
            } else {
                $formerPNum = $p;
            }
        }
    }
    say "
        formerPNum      => $formerPNum,
        nextPNum        => $nextPNum";

    $self->render(
        pNum            => $pNum,
        pageNum         => $pageNum,
        formerPNum      => $formerPNum,
        nextPNum        => $nextPNum,
        content         => $content,
        htmlFileLocal   => $htmlFileLocal,
        wordOccurences  => $wordOccurences,
        totalPages      => $totalPages,
        totalTerms      => $totalTerms,
        allTermsOnly    => $allTermsOnly,
        fileLocal       => $fileLocal,
        fileShort       => $fileShort,
        fileMd5         => $fileMd5,
        terms           => $terms,
        results         => \%results,
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub pages_from_file {
    my ($fileMd5, $allTermsOnly, $totalTerms, @terms) = @_;

    # Searching in the targeted file for specific occurences.
    my %pages = ();
    my $jsonFile = "public/pfizer_documents/json_words/$fileMd5.json";
    my $json;
    open my $in, '<:utf8', $jsonFile;
    while (<$in>) {
        $json .= $_;
    }
    close $in;
    $json = decode_json($json);
    my %fileWorlds = %$json;
    # p$json;
    my %pre_pages = ();
    for my $term (@terms) {
        next if length $term < 3;
        say "term : $term";
        if (exists $fileWorlds{$term}) {
            for my $pageNum (sort keys %{$fileWorlds{$term}}) {
                $pre_pages{$pageNum}->{$term} = 0;
            }
        }
    }
    # p%pre_pages;
    for my $pageNum (sort{$a <=> $b} keys %pre_pages) {
        if ($allTermsOnly eq 'true' && $totalTerms > 1) {
            next unless keys %{$pre_pages{$pageNum}} == $totalTerms;
        }
        my $htmlFileLocal = "public/pfizer_documents/pdf_to_html_files/$fileMd5/page$pageNum.html";
        # say "htmlFileLocal : $htmlFileLocal";
        # next;
        open my $in, '<:utf8', $htmlFileLocal;
        my $content;
        while (<$in>) {
            $content .= $_;
        }
        close $in;
        $content =~ s/src="page$pageNum\.png"/src="\/pfizer_documents\/pdf_to_html_files\/$fileMd5\/page$pageNum\.png"/;
        # $content =~ s/position:absolute;//g;
        for my $term (@terms) {
            next if length $term < 3;
            my $ucfTerm = ucfirst $term;
            my $ucTerm  = uc $term;
            $content =~ s/$term/<span style=\"background:yellow;\">$term<\/span>/g;
            $content =~ s/$ucfTerm/<span style=\"background:yellow;\">$ucfTerm<\/span>/g;
            $content =~ s/$ucTerm/<span style=\"background:yellow;\">$ucTerm<\/span>/g;
            $pages{$pageNum}->{'wordOccurences'} += $fileWorlds{$term}->{$pageNum};
        }
        $pages{$pageNum}->{'htmlFileLocal'}   = $htmlFileLocal;
        $pages{$pageNum}->{'content'}         = $content;
    }

    # p%pages;
    return %pages;
}

sub viewer {
    my $self            = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $pdf             = $self->param('pdf');
    say "pdf : $pdf";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';



    $self->render(
        pdf             => $pdf,
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub pdf_loader {
    my $self                   = shift;
    my $currentLanguage        = $self->param('currentLanguage') // 'fr';
    my $contentContainerWidth  = $self->param('contentContainerWidth');
    my $contentContainerHeight = $self->param('contentContainerHeight');
    my $pdf                    = $self->param('pdf');
    unless ($pdf || $contentContainerHeight || $contentContainerHeight) {
        $self->render(text => 'Missing mandatory data');
    }
    $pdf = '/' . $pdf;
    $contentContainerHeight = $contentContainerHeight - 20;
    say "pdf : $pdf";

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';


    $self->render(
        pdf                    => $pdf,
        currentLanguage        => $currentLanguage,
        contentContainerWidth  => $contentContainerWidth,
        contentContainerHeight => $contentContainerHeight,
        languages              => \%languages
    );
}

1;