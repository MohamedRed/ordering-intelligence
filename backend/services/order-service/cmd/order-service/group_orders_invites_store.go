package main

import (
	"context"

	cloudfirestore "cloud.google.com/go/firestore"
)

func groupOrderInviteRef(client *cloudfirestore.Client, groupID, inviteID string) *cloudfirestore.DocumentRef {
	return client.Collection(groupOrdersCollection).Doc(groupID).Collection(groupOrdersInvitesCollection).Doc(inviteID)
}

func createGroupOrderInvite(ctx context.Context, client *cloudfirestore.Client, invite groupOrderInvite) error {
	_, err := groupOrderInviteRef(client, invite.GroupOrderID, invite.InviteID).Create(ctx, invite)
	return err
}
