package OpenVaet::Controller::MiscarriagesWithinAWeek;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub miscarriages_within_a_week {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // die;


    my %languages       = ();
    $languages{'fr'}    = 'French';
    $languages{'en'}    = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages       => \%languages
    );
}

1;