package OpenVaet::Controller::AustralianData;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;

sub australian_data {

    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $australianData;
    open my $in, '<:utf8', 'australian_death_reports.json';
    while (<$in>) {
        $australianData .= $_;
    }
    close $in;
    $australianData = decode_json($australianData);
    my %australianData = %$australianData;


    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages,
        australianData  => \%australianData
    );
}

1;