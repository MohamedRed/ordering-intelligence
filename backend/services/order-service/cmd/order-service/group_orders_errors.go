package main

import "errors"

var errInvalidGroupStatus = errors.New("invalid_group_status")
var errParticipantNotFound = errors.New("participant_not_found")
var errInviteNotFound = errors.New("invite_not_found")
var errInviteExpired = errors.New("invite_expired")
var errInviteLimitReached = errors.New("invite_limit_reached")
var errInviteNotAllowed = errors.New("invite_not_allowed")

func errorsIsInvalidStatus(err error) bool {
	return errors.Is(err, errInvalidGroupStatus)
}

func errorsIsParticipantMissing(err error) bool {
	return errors.Is(err, errParticipantNotFound)
}

func errorsIsInviteNotFound(err error) bool {
	return errors.Is(err, errInviteNotFound)
}

func errorsIsInviteExpired(err error) bool {
	return errors.Is(err, errInviteExpired)
}

func errorsIsInviteLimitReached(err error) bool {
	return errors.Is(err, errInviteLimitReached)
}

func errorsIsInviteNotAllowed(err error) bool {
	return errors.Is(err, errInviteNotAllowed)
}
