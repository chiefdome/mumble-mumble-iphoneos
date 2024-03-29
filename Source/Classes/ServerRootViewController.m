/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <MumbleKit/MKAudio.h>
#import <MumbleKit/MKCertificate.h>
#import <MumbleKit/MKConnection.h>

#import "MumbleApplication.h"
#import "MumbleApplicationDelegate.h"
#import "Database.h"

#import "ServerRootViewController.h"
#import "ServerConnectionViewController.h"
#import "ChannelViewController.h"
#import "LogViewController.h"
#import "CertificateViewController.h"
#import "ServerCertificateTrustViewController.h"
#import "ChannelNavigationViewController.h"

@interface ServerRootViewController (Private)
- (void) togglePushToTalk;
- (UIView *) stateAccessoryViewForUser:(MKUser *)user;
@end

@implementation ServerRootViewController

- (id) initWithHostname:(NSString *)host port:(NSUInteger)port username:(NSString *)username password:(NSString *)password {
	NSData *certPersistentId = [[NSUserDefaults standardUserDefaults] objectForKey:@"DefaultCertificate"];
	if (certPersistentId == nil) {
		NSLog(@"ServerRootViewController: Cannot instantiate without a default certificate.");
		return nil;
	}

	if (self = [super init]) {
		_username = [username copy];
		_password = [password copy];

		_connection = [[MKConnection alloc] init];
		[_connection setDelegate:self];

		_model = [[MKServerModel alloc] initWithConnection:_connection];
		[_model addDelegate:self];

		// Try to fetch our given identity's SecIdentityRef by its persistent reference.
		// If we're able to fetch it, set it as the connection's client certificate.
		SecIdentityRef secIdentity = NULL;
		NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
									certPersistentId,		kSecValuePersistentRef,
									kCFBooleanTrue,			kSecReturnRef,
									kSecMatchLimitOne,		kSecMatchLimit,
								nil];
		if (SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef *)&secIdentity) == noErr && secIdentity != NULL) {
			[_connection setClientIdentity:secIdentity];
			CFRelease(secIdentity);
		}

		[_connection connectToHost:host port:port];
	}
	return self;
}

- (void) dealloc {
	[_username release];
	[_password release];
	[_model release];
	[_connection release];

	[super dealloc];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (void) viewWillAppear:(BOOL)animated {
	// Title
	if (_currentChannel == nil)
		[[self navigationItem] setTitle:@"Connecting..."];
	else
		[[self navigationItem] setTitle:[_currentChannel channelName]];

	// Top bar
	UIBarButtonItem *disconnectButton = [[UIBarButtonItem alloc] initWithTitle:@"Disconnect" style:UIBarButtonItemStyleBordered target:self action:@selector(disconnectClicked:)];
	[[self navigationItem] setLeftBarButtonItem:disconnectButton];
	[disconnectButton release];

	UIBarButtonItem *infoItem = [[UIBarButtonItem alloc] initWithTitle:@"Certs" style:UIBarButtonItemStyleBordered target:self action:@selector(infoClicked:)];
	[[self navigationItem] setRightBarButtonItem:infoItem];
	[infoItem release];

	// Toolbar
	UIBarButtonItem *channelsButton = [[UIBarButtonItem alloc] initWithTitle:@"Channels" style:UIBarButtonItemStyleBordered target:self action:@selector(channelsButtonClicked:)];
	UIBarButtonItem *pttButton = [[UIBarButtonItem alloc] initWithTitle:@"PushToTalk" style:UIBarButtonItemStyleBordered target:self action:@selector(pushToTalkClicked:)];
	UIBarButtonItem *usersButton = [[UIBarButtonItem alloc] initWithTitle:@"Users" style:UIBarButtonItemStyleBordered target:self action:@selector(usersButtonClicked:)];
	UIBarButtonItem *flexSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
	[self setToolbarItems:[NSArray arrayWithObjects:channelsButton, flexSpace, pttButton, flexSpace, usersButton, nil]];
	[channelsButton release];
	[pttButton release];
	[usersButton release];
	[flexSpace release];

#ifdef USE_CONNECTION_ANIMATION
	// Show the ServerConnectionViewController when we're trying to establish a
	// connection to a server.
	if (![_connection connected]) {
		_progressController = [[ServerConnectionViewController alloc] init];
		_progressController.view.frame = [[UIScreen mainScreen] applicationFrame];
		_progressController.view.hidden = YES;

		UIWindow *window = [[MumbleApp delegate] window];
		[window addSubview:_progressController.view];

		[UIView beginAnimations:nil context:NULL];
		_progressController.view.hidden = NO;
		[UIView setAnimationDuration:0.6f];
		[UIView setAnimationBeginsFromCurrentState:YES];
		[UIView setAnimationTransition:UIViewAnimationTransitionFlipFromRight forView:window cache:YES];
		[UIView commitAnimations];

		[MumbleApp setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:YES];
	}
#endif

	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	[[self navigationController] setToolbarHidden:NO];
}

- (void) viewDidAppear:(BOOL)animated {
}

#pragma mark MKConnection Delegate

// The connection encountered an invalid SSL certificate chain.
- (void) connection:(MKConnection *)conn trustFailureInCertificateChain:(NSArray *)chain {
	// Check the database whether the user trusts the leaf certificate of this server.
	NSString *storedDigest = [Database digestForServerWithHostname:[conn hostname] port:[conn port]];
	NSString *serverDigest = [[[conn peerCertificates] objectAtIndex:0] hexDigest];
	if (storedDigest) {
		// Match?
		if ([storedDigest isEqualToString:serverDigest]) {
			[conn setIgnoreSSLVerification:YES];
			[conn reconnect];
			return;

		// Mismatch.  The server is using a new certificate, different from the one it previously
		// presented to us.
		} else {
			NSString *title = @"Certificate Mismatch";
			NSString *msg = @"The server presented a different certificate than the one stored for this server";
			UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
			[alert addButtonWithTitle:@"Ignore"];
			[alert addButtonWithTitle:@"Trust New Certificate"];
			[alert addButtonWithTitle:@"Show Certificates"];
			[alert show];
			[alert release];
		}

	// No certhash of this certificate in the database for this hostname-port combo.  Let the user decide
	// what to do.
	} else {
		NSString *title = @"Unable to validate server certificate";
		NSString *msg = @"Mumble was unable to validate the certificate chain of the server.";

		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:msg delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:nil];
		[alert addButtonWithTitle:@"Ignore"];
		[alert addButtonWithTitle:@"Trust Certificate"];
		[alert addButtonWithTitle:@"Show Certificates"];
		[alert show];
		[alert release];
	}
}

// The server rejected our connection.
- (void) connection:(MKConnection *)conn rejectedWithReason:(MKRejectReason)reason explanation:(NSString *)explanation {
	NSString *title = @"Connection Rejected";
	NSString *msg = nil;

	switch (reason) {
		case MKRejectReasonNone:
			msg = @"No reason";
			break;
		case MKRejectReasonWrongVersion:
			msg = @"Version mismatch between client and server.";
			break;
		case MKRejectReasonInvalidUsername:
			msg = @"Invalid username";
			break;
		case MKRejectReasonWrongUserPassword:
			msg = @"Wrong user password";
			break;
		case MKRejectReasonWrongServerPassword:
			msg = @"Wrong server password";
			break;
		case MKRejectReasonUsernameInUse:
			msg = @"Username already in use";
			break;
		case MKRejectReasonServerIsFull:
			msg = @"Server is full";
			break;
		case MKRejectReasonNoCertificate:
			msg = @"A certificate is needed to connect to this server";
			break;
	}

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:msg delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[alert show];
	[alert release];

	[[self navigationController] dismissModalViewControllerAnimated:YES];
}

// Connection established...
- (void) connectionOpened:(MKConnection *)conn {
	[conn authenticateWithUsername:_username password:_password];
}

// Connection closed...
- (void) connectionClosed:(MKConnection *)conn {
	NSLog(@"ServerRootViewController: Connection closed");
}

#pragma mark MKServerModel Delegate

// We've successfuly joined the server.
- (void) serverModel:(MKServerModel *)server joinedServerAsUser:(MKUser *)user {
	_currentChannel = [[_model connectedUser] channel];
	_channelUsers = [[[[_model connectedUser] channel] users] mutableCopy];

#ifdef USE_CONNECTION_ANIMATION
	[MumbleApp setStatusBarStyle:UIStatusBarStyleDefault animated:YES];

	[UIView animateWithDuration:0.4f animations:^{
		_progressController.view.alpha = 0.0f;
	} completion:^(BOOL finished){
		[_progressController.view removeFromSuperview];
		[_progressController release];
		_progressController = nil;
	}];
#endif

	[[self navigationItem] setTitle:[_currentChannel channelName]];
	[[self tableView] reloadData];
}

// A user joined the server.
- (void) serverModel:(MKServerModel *)server userJoined:(MKUser *)user {
	NSLog(@"ServerViewController: userJoined.");
}

// A user left the server.
- (void) serverModel:(MKServerModel *)server userLeft:(MKUser *)user {
	if (_currentChannel == nil)
		return;

	NSUInteger userIndex = [_channelUsers indexOfObject:user];
	if (userIndex != NSNotFound) {
		[_channelUsers removeObjectAtIndex:userIndex];
		[[self tableView] deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]]
								withRowAnimation:UITableViewRowAnimationRight];
	}
}

// A user moved channel
- (void) serverModel:(MKServerModel *)server userMoved:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)mover {
	if (_currentChannel == nil)
		return;

	// Was this ourselves, or someone else?
	if (user != [server connectedUser]) {
		// Did the user join this channel?
		if (chan == _currentChannel) {
			[_channelUsers addObject:user];
			NSUInteger userIndex = [_channelUsers indexOfObject:user];
			[[self tableView] insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]]
									withRowAnimation:UITableViewRowAnimationLeft];
		// Or did he leave it?
		} else {
			NSUInteger userIndex = [_channelUsers indexOfObject:user];
			if (userIndex != NSNotFound) {
				[_channelUsers removeObjectAtIndex:userIndex];
				[[self tableView] deleteRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]]
										withRowAnimation:UITableViewRowAnimationRight];
			}
		}

	// We were moved. We need to redo the array holding the users of the
	// current channel.
	} else {
		NSUInteger numUsers = [_channelUsers count];
		[_channelUsers release];
		_channelUsers = nil;

		NSMutableArray *array = [[NSMutableArray alloc] init];
		for (NSUInteger i = 0; i < numUsers; i++) {
			[array addObject:[NSIndexPath indexPathForRow:i inSection:0]];
		}
		[[self tableView] deleteRowsAtIndexPaths:array withRowAnimation:UITableViewRowAnimationRight];

		_currentChannel = chan;
		_channelUsers = [[chan users] mutableCopy];

		[array removeAllObjects];
		numUsers = [_channelUsers count];
		for (NSUInteger i = 0; i < numUsers; i++) {
			[array addObject:[NSIndexPath indexPathForRow:i inSection:0]];
		}
		[[self tableView] insertRowsAtIndexPaths:array withRowAnimation:UITableViewRowAnimationLeft];
		[array release];

		// Update the title to match our new channel.
		[[self navigationItem] setTitle:[_currentChannel channelName]];
	}
}

// A channel was added.
- (void) serverModel:(MKServerModel *)server channelAdded:(MKChannel *)channel {
	NSLog(@"ServerViewController: channelAdded.");
}

// A channel was removed.
- (void) serverModel:(MKServerModel *)server channelRemoved:(MKChannel *)channel {
	NSLog(@"ServerViewController: channelRemoved.");
}

- (void) serverModel:(MKServerModel *)model userSelfMuted:(MKUser *)user {
}

- (void) serverModel:(MKServerModel *)model userRemovedSelfMute:(MKUser *)user {
}

- (void) serverModel:(MKServerModel *)model userSelfMutedAndDeafened:(MKUser *)user {
}

- (void) serverModel:(MKServerModel *)model userRemovedSelfMuteAndDeafen:(MKUser *)user {
}

- (void) serverModel:(MKServerModel *)model userSelfMuteDeafenStateChanged:(MKUser *)user {
	NSUInteger userIndex = [_channelUsers indexOfObject:user];
	if (userIndex != NSNotFound) {
		[[self tableView] reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
	}
}

// --

- (void) serverModel:(MKServerModel *)model userMutedAndDeafened:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ muted and deafened by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userUnmutedAndUndeafened:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ unmuted and undeafened by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userMuted:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ muted by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userUnmuted:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ unmuted by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userDeafened:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ deafened by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userUndeafened:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ undeafened by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userSuppressed:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ suppressed by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userUnsuppressed:(MKUser *)user byUser:(MKUser *)actor {
	NSLog(@"%@ unsuppressed by %@", user, actor);
}

- (void) serverModel:(MKServerModel *)model userMuteStateChanged:(MKUser *)user {
	NSInteger userIndex = [_channelUsers indexOfObject:user];
	if (userIndex != NSNotFound) {
		[[self tableView] reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
	}
}

// --

- (void) serverModel:(MKServerModel *)model userPrioritySpeakerChanged:(MKUser *)user {
	NSInteger userIndex = [_channelUsers indexOfObject:user];
	if (userIndex != NSNotFound) {
		[[self tableView] reloadRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:userIndex inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
	}
}

- (void) serverModel:(MKServerModel *)server userTalkStateChanged:(MKUser *)user {
	NSUInteger userIndex = [_channelUsers indexOfObject:user];
	if (userIndex == NSNotFound)
		return;

	UITableViewCell *cell = [[self tableView] cellForRowAtIndexPath:[NSIndexPath indexPathForRow:userIndex inSection:0]];
	MKTalkState talkState = [user talkState];
	NSString *talkImageName = nil;
	if (talkState == MKTalkStatePassive)
		talkImageName = @"talking_off";
	else if (talkState == MKTalkStateTalking)
		talkImageName = @"talking_on";
	else if (talkState == MKTalkStateWhispering)
		talkImageName = @"talking_whisper";
	else if (talkState == MKTalkStateShouting)
		talkImageName = @"talking_alt";

	[[cell imageView] setImage:[UIImage imageNamed:talkImageName]];
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [_channelUsers count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    }

	NSUInteger row = [indexPath row];
	MKUser *user = [_channelUsers objectAtIndex:row];

	cell.textLabel.text = [user userName];
	if ([_model connectedUser] == user) {
		cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0f];
	} else {
		cell.textLabel.font = [UIFont systemFontOfSize:14.0f];
	}

	MKTalkState talkState = [user talkState];
	NSString *talkImageName = nil;
	if (talkState == MKTalkStatePassive)
		talkImageName = @"talking_off";
	else if (talkState == MKTalkStateTalking)
		talkImageName = @"talking_on";
	else if (talkState == MKTalkStateWhispering)
		talkImageName = @"talking_whisper";
	else if (talkState == MKTalkStateShouting)
		talkImageName = @"talking_alt";
	cell.imageView.image = [UIImage imageNamed:talkImageName];

	cell.accessoryView = [self stateAccessoryViewForUser:user];

    return cell;
}

- (UIView *) stateAccessoryViewForUser:(MKUser *)user {
	const CGFloat iconHeight = 28.0f;
	const CGFloat iconWidth = 22.0f;

	NSMutableArray *states = [[NSMutableArray alloc] init];
	if ([user isAuthenticated])
		[states addObject:@"authenticated"];
	if ([user isSelfDeafened])
		[states addObject:@"deafened_self"];
	if ([user isSelfMuted])
		[states addObject:@"muted_self"];
	if ([user isMuted])
		[states addObject:@"muted_server"];
	if ([user isDeafened])
		[states addObject:@"deafened_server"];
	if ([user isLocalMuted])
		[states addObject:@"muted_local"];
	if ([user isSuppressed])
		[states addObject:@"muted_suppressed"];
	if ([user isPrioritySpeaker])
		[states addObject:@"priorityspeaker"];

	CGFloat widthOffset = [states count] * iconWidth;
	UIView *stateView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, widthOffset, iconHeight)];
	for (NSString *imageName in states) {
		UIImage *img = [UIImage imageNamed:imageName];
		UIImageView *imgView = [[UIImageView alloc] initWithImage:img];
		CGFloat ypos = (iconHeight - img.size.height)/2.0f;
		CGFloat xpos = (iconWidth - img.size.width)/2.0f;
		widthOffset -= iconWidth - xpos;
		imgView.frame = CGRectMake(widthOffset, ypos, img.size.width, img.size.height);
		[stateView addSubview:imgView];
	}

	[states release];
	return [stateView autorelease];
}

#pragma mark -
#pragma mark UITableView delegate

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 28.0f;
}

#pragma mark -
#pragma mark UIAlertView delegate

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	// Cancel
	if (buttonIndex == 0) {
		// Tear down the connection.
		[_connection disconnect];

	// Ignore
	} else if (buttonIndex == 1) {
		// Ignore just reconnects to the server without
		// performing any verification on the certificate chain
		// the server presents us.
		[_connection setIgnoreSSLVerification:YES];
		[_connection reconnect];

	// Trust
	} else if (buttonIndex == 2) {
		// Store the cert hash of the leaf certificate.  We then ignore certificate
		// verification errors from this host as long as it keeps on presenting us
		// the same certificate it always has.
		NSString *digest = [[[_connection peerCertificates] objectAtIndex:0] hexDigest];
		[Database storeDigest:digest forServerWithHostname:[_connection hostname] port:[_connection port]];
		[_connection setIgnoreSSLVerification:YES];
		[_connection reconnect];

	// Show certificates
	} else if (buttonIndex == 3) {
		ServerCertificateTrustViewController *certTrustView = [[ServerCertificateTrustViewController alloc] initWithConnection:_connection];
		UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:certTrustView];
		[certTrustView release];
		[self presentModalViewController:navCtrl animated:YES];
		[navCtrl release];
	}
}

#pragma mark -
#pragma mark Target/actions

// Disconnect from the server
- (void) disconnectClicked:(id)sender {
	[_connection disconnect];
	[[self navigationController] dismissModalViewControllerAnimated:YES];
}

// Info (certs) button clicked
- (void) infoClicked:(id)sender {
	NSArray *certs = [_connection peerCertificates];
	CertificateViewController *certView = [[CertificateViewController alloc] initWithCertificates:certs];
	[[self navigationController] pushViewController:certView animated:YES];
	[certView release];
}

// Push-to-Talk button
- (void) pushToTalkClicked:(id)sender {
	[self togglePushToTalk];
}

// Channel picker
- (void) channelsButtonClicked:(id)sender {
	ChannelNavigationViewController *channelView = [[ChannelNavigationViewController alloc] initWithServerModel:_model];
	UINavigationController *navCtrl = [[UINavigationController alloc] initWithRootViewController:channelView];
	[channelView release];
	[[self navigationController] presentModalViewController:navCtrl animated:YES];
	[navCtrl release];
}

// User picker
- (void) usersButtonClicked:(id)sender {
	NSLog(@"users");
}

- (void) togglePushToTalk {
	_pttState = !_pttState;
	MKAudio *audio = [MKAudio sharedAudio];
	[audio setForceTransmit:_pttState];
}

@end
