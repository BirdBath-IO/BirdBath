package BirdBath::Plugin::OAuth2;

use Mojo::Base 'Mojolicious::Plugin';
use MojoX::OAuth2::Client;

has 'app';

sub register {
	my ($self, $app) = @_;
	$self->app($app);

	$app->helper(oauth2 => sub {
		my $self = shift;
		my $oauth2 = MojoX::OAuth2::Client->new;
		$oauth2->identity_providers($self->app->config->{oauth2_providers});
		return $oauth2;
	});

	my $r = $self->app->routes;
	$r->get('/login')->to('o_auth2#choose');
    $r->get('/oauth2/login')->to('o_auth2#login');
    $r->get('/oauth2/callback')->to('o_auth2#callback');
}

1;