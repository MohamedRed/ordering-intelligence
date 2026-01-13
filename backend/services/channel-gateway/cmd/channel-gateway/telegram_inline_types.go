package main

type telegramInlineQuery struct {
	ID     string        `json:"id"`
	From   *telegramUser `json:"from"`
	Query  string        `json:"query"`
	Offset string        `json:"offset"`
}

type telegramInlineMessageContent struct {
	MessageText           string `json:"message_text"`
	ParseMode             string `json:"parse_mode,omitempty"`
	DisableWebPagePreview bool   `json:"disable_web_page_preview,omitempty"`
}

type telegramInlineKeyboardMarkup struct {
	InlineKeyboard [][]telegramInlineKeyboardButton `json:"inline_keyboard"`
}

type telegramInlineKeyboardButton struct {
	Text   string              `json:"text"`
	WebApp *telegramWebAppInfo `json:"web_app,omitempty"`
	URL    string              `json:"url,omitempty"`
}

type telegramWebAppInfo struct {
	URL string `json:"url"`
}

type telegramInlineQueryResult struct {
	Type                string                        `json:"type"`
	ID                  string                        `json:"id"`
	Title               string                        `json:"title"`
	Description         string                        `json:"description,omitempty"`
	InputMessageContent telegramInlineMessageContent  `json:"input_message_content"`
	ReplyMarkup         *telegramInlineKeyboardMarkup `json:"reply_markup,omitempty"`
}

type telegramInlineQueryAnswer struct {
	InlineQueryID string                      `json:"inline_query_id"`
	Results       []telegramInlineQueryResult `json:"results"`
	CacheTime     int                         `json:"cache_time,omitempty"`
	IsPersonal    bool                        `json:"is_personal,omitempty"`
	NextOffset    string                      `json:"next_offset,omitempty"`
}
