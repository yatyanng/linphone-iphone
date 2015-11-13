/* OutgoingCallViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "CallOutgoingView.h"
#import "PhoneMainView.h"

@implementation CallOutgoingView

#pragma mark - UICompositeViewDelegate Functions

static UICompositeViewDescription *compositeDescription = nil;

+ (UICompositeViewDescription *)compositeViewDescription {
	if (compositeDescription == nil) {
		compositeDescription = [[UICompositeViewDescription alloc] init:self.class
															  statusBar:StatusBarView.class
																 tabBar:nil
															   sideMenu:SideMenuView.class
															 fullscreen:false
														  landscapeMode:LinphoneManager.runningOnIpad
														   portraitMode:true];
		compositeDescription.darkBackground = true;
	}
	return compositeDescription;
}

- (UICompositeViewDescription *)compositeViewDescription {
	return self.class.compositeViewDescription;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];

	LinphoneCall *call = linphone_core_get_current_call([LinphoneManager getLc]);
	if (!call) {
		[PhoneMainView.instance popCurrentView];
	} else {
		const LinphoneAddress *addr = linphone_call_get_remote_address(call);
		[ContactDisplay setDisplayNameLabel:_nameLabel forAddress:addr];
		char *uri = linphone_address_as_string_uri_only(addr);
		_addressLabel.text = [NSString stringWithUTF8String:uri];
		ms_free(uri);
		[_avatarImage setImage:[FastAddressBook imageForAddress:addr thumbnail:NO] bordered:YES withRoundedRadius:YES];
	}
}

- (IBAction)onDeclineClick:(id)sender {
	LinphoneCall *call = linphone_core_get_current_call([LinphoneManager getLc]);
	if (call) {
		linphone_core_terminate_call([LinphoneManager getLc], call);
	}
	[PhoneMainView.instance popCurrentView];
}
@end