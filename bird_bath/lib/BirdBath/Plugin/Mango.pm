package BirdBath::Plugin::Mango;

use Mojo::Base 'Mojolicious::Plugin';

has 'app';

sub register {
	my ($self, $app) = @_;
	$self->app($app);

	$app->helper(mango => sub {
		state $mango = Mango->new($app->config->{mongodb}->{uri});
		return $mango;
	});

	$app->helper(tweets => sub {
		my $self = shift;
		return $self->app->mango->db('birdbath')->collection('tweets');
	});

	$app->helper(accounts => sub {
		my $self = shift;
		return $self->app->mango->db('birdbath')->collection('accounts');
	});

	$app->helper(users => sub {
		my $self = shift;
		return $self->app->mango->db('birdbath')->collection('users');
	});
}

1;