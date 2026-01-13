package main

import (
	"context"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
)

func joinGroupOrderWithInvite(
	ctx context.Context,
	client *cloudfirestore.Client,
	groupID string,
	inviteID string,
	participantID string,
	displayName string,
	contact channelContact,
) (groupOrderSession, error) {
	var updated groupOrderSession
	err := client.RunTransaction(ctx, func(ctx context.Context, tx *cloudfirestore.Transaction) error {
		groupRef := client.Collection(groupOrdersCollection).Doc(groupID)
		groupSnap, err := tx.Get(groupRef)
		if err != nil {
			return err
		}
		var current groupOrderSession
		if err := groupSnap.DataTo(&current); err != nil {
			return err
		}
		if current.Status != groupOrderStatusOpen {
			return errInvalidGroupStatus
		}
		for _, p := range current.Participants {
			if p.ParticipantID == participantID {
				updated = current
				return nil
			}
		}
		if inviteID == "" {
			return errInviteNotFound
		}
		inviteRef := groupOrderInviteRef(client, groupID, inviteID)
		inviteSnap, err := tx.Get(inviteRef)
		if err != nil {
			return errInviteNotFound
		}
		var invite groupOrderInvite
		if err := inviteSnap.DataTo(&invite); err != nil {
			return err
		}
		if time.Now().UTC().After(invite.ExpiresAt) {
			return errInviteExpired
		}
		if invite.MaxUses > 0 && invite.UsesCount >= invite.MaxUses {
			return errInviteLimitReached
		}
		invite.UsesCount++
		invite.UsedAt = time.Now().UTC()
		invite.UsedByID = participantID
		if err := tx.Set(inviteRef, invite); err != nil {
			return err
		}
		if displayName == "" {
			displayName = contact.DisplayName
		}
		current.Participants = append(current.Participants, groupOrderParticipant{
			ParticipantID: participantID,
			Contact:       contact,
			DisplayName:   displayName,
		})
		if current.CreatedAt.IsZero() {
			current.CreatedAt = time.Now().UTC()
		}
		current.UpdatedAt = time.Now().UTC()
		updated = current
		return tx.Set(groupRef, current)
	})
	return updated, err
}
