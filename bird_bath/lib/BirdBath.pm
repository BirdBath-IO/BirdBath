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
  	return $self->redirect_to('/login') unless $self->session->{user};
  	return 1;
  });
  my $account = $auth->bridge->to(cb => sub {
  	my $self = shift;
  	my $args = { 
  		screen_name_lc => lc($self->req->json->{account}),
  		'users.id' => $self->session->{user}->{id},
  		'users.provider' => $self->session->{user}->{provider},
  	};
  	$self->accounts->find_one($args => sub {
  		my ($mango, $error, $doc) = @_;
  		die("DB error") if $error;
  		die("Not found") if !$doc;
  		$self->stash(account => $doc);
  		my $u;
  		for my $user (@{$doc->{users}}) {
	  		if($user->{id} eq $self->session->{user}->{id} &&
	  		   $user->{provider} eq $self->session->{user}->{provider}) {
	  			$u = $user;
	  			last;
	  		}
	  	}
	  	$self->stash(account_user => $u);
  		$self->continue;
  	});
  	return undef;
  });
  my $contributor = $account->bridge->to(cb => sub {
  	my $self = shift;
  	my $u = $self->stash('account_user');
  	
  	die("Not a contributor") if !$u;
  	die("Not a contributor") if $u->{role} !~ /^(admin|editor|contributor)$/;
  	return 1;
  });
  my $editor = $account->bridge->to(cb => sub {
  	my $self = shift;
  	my $u = $self->stash('account_user');
  	
  	die("Not a editor") if !$u;
  	die("Not a editor") if $u->{role} !~ /^(admin|editor)$/;
  	return 1;
  });
  my $admin = $account->bridge->to(cb => sub {
  	my $self = shift;
  	my $u = $self->stash('account_user');
  	
  	die("Not a admin") if !$u;
  	die("Not a admin") if $u->{role} !~ /^(admin)$/;
  	return 1;
  });

  # View only or any auth user
  $auth->get('/manage')->to('manage#welcome');
  $auth->get('/tweets')->to('home#tweets');
  $auth->get('/accounts')->to('home#accounts');
  $auth->post('/request')->to('home#request');
  $auth->post('/search')->to('search#search');
  $auth->post('/timeline')->to('search#timeline');
  $auth->post('/account-remove')->to('home#remove_account');

  # Contributor only
  $contributor->post('/tweets')->to('home#tweet');
  $contributor->post('/retweet')->to('home#retweet');

  # Editor only
  $editor->post('/approve')->to('home#approve');
  $editor->post('/reject')->to('home#reject');
  $editor->post('/undo')->to('home#undo');
  $editor->post('/update')->to('home#update');

  # Admin only
  $admin->post('/user-approve')->to('home#accept_user');
  $admin->post('/user-reject')->to('home#reject_user');
  $admin->post('/user-save')->to('home#save_user');  
  $admin->post('/user-remove')->to('home#remove_user');
}

1;
