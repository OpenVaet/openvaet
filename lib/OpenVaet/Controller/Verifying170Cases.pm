package OpenVaet::Controller::Verifying170Cases;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub verifying_170_cases {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

1;