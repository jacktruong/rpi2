#!/usr/bin/perl

open( HANDLE, "/home/kiosk/.emerge |" );

while( <HANDLE> ) {
    $_ =~ s/WARNING URL : (.*)/$1/;
    system( 'chromium-browser ' . $_ );
}
