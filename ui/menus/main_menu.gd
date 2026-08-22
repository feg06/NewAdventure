extends Control

@onready var btn_solo: Button = $VBox/BtnSolo
@onready var btn_host: Button = $VBox/BtnHost
@onready var btn_join: Button = $VBox/BtnJoin
@onready var ip_input: LineEdit = $VBox/IpInput
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	btn_solo.pressed.connect(_on_solo_pressed)
	btn_host.pressed.connect(_on_host_pressed)
	btn_join.pressed.connect(_on_join_pressed)

	MultiplayerManager.connection_failed.connect(_on_conn_failed)
	MultiplayerManager.server_disconnected.connect(_on_disconnected)

func _on_solo_pressed() -> void:
	status_label.text = "Starting Solo..."
	MultiplayerManager.start_solo_game()

func _on_host_pressed() -> void:
	status_label.text = "Hosting on port 7777..."
	var err = MultiplayerManager.host_game()
	if err != OK:
		status_label.text = "Host Error: %d" % err

func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	status_label.text = "Connecting to %s..." % ip
	var err = MultiplayerManager.join_game(ip)
	if err != OK:
		status_label.text = "Join Error: %d" % err

func _on_conn_failed() -> void:
	status_label.text = "Failed to connect!"

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."
