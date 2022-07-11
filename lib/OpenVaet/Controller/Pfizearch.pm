package OpenVaet::Controller::Pfizearch;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

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

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

sub search {
    my $self            = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $terms           = lc $self->param('terms');
    my @terms;

    # Loggin session if unknown.
    session::session_from_self($self);
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Breaks down the incoming normalized request.
    if ($terms) {
        @terms = split '[\{\}\*\[\]=\'\"\(\)_\-\\\\/,;.:+#!? ]', $terms;
    }

    # Loading JSON data.
    my $pfizFile   = 'stats/pfizer_json_data.json';
    my $filesFound = 0;
    my @results    = ();
    if (-f $pfizFile && $terms) {
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
        for my $term (@terms) {
            for my $word (keys %{%$json{'words'}}) {
                if ($word =~ /term/) {
                    for my $fileRef (keys %{%$json{'words'}->{$word}}) {
                        my $wordOccurences = %$json{'words'}->{$word}->{$fileRef} // die;
                        $pre_results{$fileRef} += $wordOccurences;
                    }
                }
            }
        }

        # Sorting results by occurences.
        my %results    = ();
        for my $fileRef (sort{$b <=> $a} keys %pre_results) {
            $filesFound++;
            my $wordOccurences = $pre_results{$fileRef} // die;
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
        currentLanguage => $currentLanguage,
        terms           => $terms,
        filesFound      => $filesFound,
        languages       => \%languages,
        results         => \@results
    );
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