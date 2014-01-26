package BirdBath::Plugin::Routes;

use Mojo::Base 'Mojolicious::Plugin';

has 'app';

sub register {
	my ($self, $app) = @_;
	$self->app($app);

	push @{$app->routes->namespaces}, 'BirdBath::Controller';

	my $r = $app->routes->bridge('/')->name('root')->to(cb => sub {
		my ($self) = @_;
		$self->stash(user => $self->session->{user});
	});

	my $auth = $r->bridge->name('auth')->to(cb => sub {
		my $self = shift;
		return $self->redirect_to('/login') unless $self->session->{user};
		return 1;
	});

	my $account = $auth->bridge->name('account')->to(cb => sub {
		my $self = shift;
		my $args = { 
			screen_name_lc => lc($self->req->json->{account}),
			'users.id' => $self->session->{user}->{id},
			'users.provider' => $self->session->{user}->{provider},
		};
		$self->accounts->find_one($args => sub {
			my ($mango, $error, $doc) = @_;
			if($error) {
				$self->log->debug("Database error: $error");
				$self->render_exception("Database error");
				return 0;
			}
			if(!$doc) {
				$self->render(status => 404, text => 'Account not found');
				return 0;
			}
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

	$account->bridge->name('contributor')->to(cb => sub {
		my $self = shift;
		my $u = $self->stash('account_user');

		if(!$u || $u->{role} !~ /^(admin|editor|contributor)$/) {
			$self->render(status => 401, text => 'Permission denied');
			return 0;
		}

		return 1;
	});

	$account->bridge->name('editor')->to(cb => sub {
		my $self = shift;
		my $u = $self->stash('account_user');
		
		if(!$u || $u->{role} !~ /^(admin|editor)$/) {
			$self->render(status => 401, text => 'Permission denied');
			return 0;
		}

		return 1;
	});

	$account->bridge->name('admin')->to(cb => sub {
		my $self = shift;
		my $u = $self->stash('account_user');
		
		if(!$u || $u->{role} !~ /^(admin)$/) {
			$self->render(status => 401, text => 'Permission denied');
			return 0;
		}

		return 1;
	});
}

1;