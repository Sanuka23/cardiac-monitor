import asyncio

from bson import ObjectId

from app.services import shared_devices
from app.services.shared_devices import parse_device_ids, user_scope_filter, with_shared_devices

USER = {"_id": ObjectId("65dec42fbb74c16d06c15b57")}


def test_parse_device_ids_handles_blanks_and_spaces():
    assert parse_device_ids("") == []
    assert parse_device_ids(" ESP32_21E5F0 , PLAYBACK_DEVICE_REC ,,") == ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]


def test_with_shared_devices_keeps_own_devices_first_without_duplicates(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"])
    assert with_shared_devices(["MY_DEVICE", "ESP32_21E5F0"]) == ["MY_DEVICE", "ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]
    assert with_shared_devices([]) == ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]


def test_user_scope_filter_includes_shared_devices(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: ["ESP32_21E5F0"])
    assert user_scope_filter(USER) == {
        "$or": [{"user_id": "65dec42fbb74c16d06c15b57"}, {"device_id": {"$in": ["ESP32_21E5F0"]}}]
    }


def test_user_scope_filter_is_unchanged_without_shared_devices(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: [])
    assert user_scope_filter(USER) == {"user_id": "65dec42fbb74c16d06c15b57"}
    assert with_shared_devices(["MY_DEVICE"]) == ["MY_DEVICE"]


class FakeVitals:
    def __init__(self, device_ids):
        self.device_ids = device_ids

    async def distinct(self, field):
        assert field == "device_id"
        return list(self.device_ids)


class FakeDb:
    def __init__(self, device_ids):
        self.vitals = FakeVitals(device_ids)


UPLOADED = ["PLAYBACK_PTBXL", "ESP32_NEW001", "ESP32_21E5F0", "PLAYBACK_DEVICE_REC", "MY_DEVICE"]


def test_star_is_not_a_device_id(monkeypatch):
    monkeypatch.setattr(shared_devices.settings, "SHARED_DEVICE_IDS", "ESP32_21E5F0, *")
    assert shared_devices.shared_device_ids() == ["ESP32_21E5F0"]
    assert shared_devices.all_devices_shared()
    monkeypatch.setattr(shared_devices.settings, "SHARED_DEVICE_IDS", "ESP32_21E5F0")
    assert not shared_devices.all_devices_shared()


def test_star_adds_every_uploading_device_except_playback(monkeypatch):
    monkeypatch.setattr(shared_devices.settings, "SHARED_DEVICE_IDS", "ESP32_21E5F0,PLAYBACK_DEVICE_REC,*")
    ids = asyncio.run(shared_devices.visible_device_ids(FakeDb(UPLOADED), ["MY_DEVICE"]))
    # own first, then named shared devices (playback allowed when named), then other uploaders
    assert ids == ["MY_DEVICE", "ESP32_21E5F0", "PLAYBACK_DEVICE_REC", "ESP32_NEW001"]
    assert "PLAYBACK_PTBXL" not in ids


def test_without_star_only_named_devices_are_added(monkeypatch):
    monkeypatch.setattr(shared_devices.settings, "SHARED_DEVICE_IDS", "ESP32_21E5F0")
    ids = asyncio.run(shared_devices.visible_device_ids(FakeDb(UPLOADED), []))
    assert ids == ["ESP32_21E5F0"]


def test_star_scope_covers_the_visible_device_list(monkeypatch):
    monkeypatch.setattr(shared_devices.settings, "SHARED_DEVICE_IDS", "*")
    user = dict(USER, device_ids=["ESP32_21E5F0", "ESP32_NEW001"])
    assert user_scope_filter(user) == {
        "$or": [{"user_id": "65dec42fbb74c16d06c15b57"}, {"device_id": {"$in": ["ESP32_21E5F0", "ESP32_NEW001"]}}]
    }
