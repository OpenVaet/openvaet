package OpenVaet::Controller::CdcMortality;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub cdc_mortality {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;
    my $cdcSourceId     = 2;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching data.
    my $statsFile = 'stats/cdc_mortality.json';
    my $json;
    open my $in, '<:utf8', $statsFile;
    while (<$in>) {
        $json = $_;
    }
    close $in;
    $json = decode_json($json);

    $self->render(
        environment     => $environment,
        currentLanguage => $currentLanguage,
        statistics      => \%$json,
        languages       => \%languages
    );
}

1;