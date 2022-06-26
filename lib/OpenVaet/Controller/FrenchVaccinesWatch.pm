package OpenVaet::Controller::FrenchVaccinesWatch;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub french_vaccines_watch {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $ansmFile = "stats/ansm_data.json";
    my $json;
    open my $in, '<:utf8', $ansmFile;
    while (<$in>) {
    	$json = $_;
    }
    close $in;
    $json = decode_json($json);
    my %statistics = %$json;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        statistics      => \%statistics
    );
}

1;