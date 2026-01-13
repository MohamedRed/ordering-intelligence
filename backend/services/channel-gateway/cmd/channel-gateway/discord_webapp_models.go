package main

import "errors"

type discordWebAppSessionStartRequest struct {
	Code            string `json:"code"`
	RedirectURI     string `json:"redirectUri"`
	AccessToken     string `json:"accessToken"`
	StoreID         string `json:"storeId"`
	Locale          string `json:"locale"`
	StartGroupOrder bool   `json:"startGroupOrder"`
}

type discordOAuthTokenResponse struct {
	AccessToken string `json:"access_token"`
	TokenType   string `json:"token_type"`
	ExpiresIn   int    `json:"expires_in"`
	Scope       string `json:"scope"`
}

type discordUserResponse struct {
	ID         string `json:"id"`
	Username   string `json:"username"`
	GlobalName string `json:"global_name"`
	Locale     string `json:"locale"`
}

var errDiscordNotConfigured = errors.New("discord_not_configured")
