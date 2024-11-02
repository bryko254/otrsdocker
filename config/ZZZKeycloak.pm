# Save this as config/ZZZKeycloak.pm
package Kernel::Config::Files::ZZZKeycloak;

use strict;
use warnings;

sub Load {
    my ($File, $Self) = @_;

    # Configure External Authentication
    $Self->{AuthModule} = 'Kernel::System::Auth::HTTPBasic';
    
    # Keycloak Configuration
    $Self->{'AuthModule::HTTPBasic::Config'} = {
        # Your Keycloak realm URL (updated port)
        KeycloakURL => 'http://keycloak:8081/auth/realms/otrs',
        
        # Client configuration
        ClientID => 'otrs',
        ClientSecret => 'your-client-secret',
        
        # User attribute mapping
        UserAttributeMap => {
            UserID => 'preferred_username',
            Email => 'email',
            FirstName => 'given_name',
            LastName => 'family_name',
        },
        
        # Optional: Groups mapping
        GroupAttributeName => 'groups',
        GroupMap => {
            'keycloak-admin' => ['admin'],
            'keycloak-users' => ['users'],
        },
    };

    # SSO Login screen configuration (updated ports)
    $Self->{LoginURL} = 'http://keycloak:8081/auth/realms/otrs/protocol/openid-connect/auth';
    $Self->{LogoutURL} = 'http://keycloak:8081/auth/realms/otrs/protocol/openid-connect/logout';
}

1;
