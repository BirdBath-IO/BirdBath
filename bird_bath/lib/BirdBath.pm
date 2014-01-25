package BirdBath;
use Mojo::Base 'Mojolicious';
use Mango;

sub startup {
  my $self = shift;

  my $config = $self->plugin('Config');
  $self->config($config);

  $self->helper(oauth2 => sub {
  	my $self = shift;
  	my $oauth2 = MojoX::OAuth2::Client->new;
  	$oauth2->identity_providers($self->config->{oauth2_providers});
  	return $oauth2;
  });

  $self->helper(mango => sub {
  	state $mango = Mango->new;
  	return $mango;
  });

  $self->helper(tweets => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('tweets');
  });

  $self->helper(accounts => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('accounts');
  });

  $self->helper(users => sub {
  	my $self = shift;
  	return $self->mango->db('birdbath')->collection('users');
  });

  my $r = $self->routes->bridge('/')->to(cb => sub {
  	my ($self) = @_;
  	$self->stash(user => $self->session->{user});
  });

  $r->get('/')->to('home#welcome');
  $r->get('/logout')->to('home#logout');
  $r->get('/twitter')->to('twitter#twitter');
  $r->get('/twitter/callback')->to('twitter#callback');

  $r->get('/login')->to('o_auth2#choose');
  $r->get('/oauth2/login')->to('o_auth2#login');
  $r->get('/oauth2/callback')->to('o_auth2#callback');

  my $auth = $r->bridge->to(cb => sub {
  	my $self = shift;
  	return 0 unless $self->session->{user};
  	return 1;
  });
  $auth->get('/tweets')->to('home#tweets');
  $auth->post('/tweets')->to('home#tweet');
  $auth->get('/accounts')->to('home#accounts');
  $auth->post('/approve')->to('home#approve');
  $auth->post('/reject')->to('home#reject');
  $auth->post('/undo')->to('home#undo');
  $auth->post('/update')->to('home#update');
}

1;
