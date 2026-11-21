class_name CardDeck
extends Resource
## 抽卡用的卡牌內容。實際的卡牌寫在 lesson/card_draw/data/card_deck.tres。
##
## 想改卡牌：在 Godot 的檔案系統面板點兩下 card_deck.tres，
## 在右邊的檢查器裡改三個文字框，一行就是一張卡。空白行會被略過。

## 殺手個性卡（在殺手的檢查器調「個性」和「開關」），一行一張
@export_multiline var killers: String = ""
## 場景卡（房子蓋成什麼樣：牆、玻璃、草叢怎麼擺），一行一張
@export_multiline var places: String = ""
## 目標組合卡（要放哪些任務、出口怎麼設定），一行一張
@export_multiline var goals: String = ""


## 把「一行一張」的文字拆成卡牌清單：去掉每行前後的空白，略過空白行
static func split_cards(text: String) -> PackedStringArray:
	var cards: PackedStringArray = []
	for line: String in text.split("\n"):
		var card: String = line.strip_edges()
		if card != "":
			cards.append(card)
	return cards
