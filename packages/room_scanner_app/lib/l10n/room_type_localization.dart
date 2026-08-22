import 'package:room_scanner_core/room_scanner_core.dart';

import 'generated/app_localizations.dart';

extension LocalizedRoomType on RoomType {
  String localizedName(
    AppLocalizations l10n,
  ) {
    switch (this) {
      case RoomType.living:
        return l10n.roomTypeLiving;
      case RoomType.cocina:
        return l10n.roomTypeKitchen;
      case RoomType.bano:
        return l10n.roomTypeBathroom;
      case RoomType.dormitorio:
        return l10n.roomTypeBedroom;
      case RoomType.lavadero:
        return l10n.roomTypeLaundry;
      case RoomType.pasillo:
        return l10n.roomTypeHallway;
      case RoomType.comedor:
        return l10n.roomTypeDiningRoom;
      case RoomType.comedorDiario:
        return l10n.roomTypeDailyDiningRoom;
      case RoomType.patio:
        return l10n.roomTypePatio;
      case RoomType.hall:
        return l10n.roomTypeHall;
      case RoomType.balcon:
        return l10n.roomTypeBalcony;
      case RoomType.terraza:
        return l10n.roomTypeTerrace;
      case RoomType.cochera:
        return l10n.roomTypeGarage;
      case RoomType.playroom:
        return l10n.roomTypePlayroom;
      case RoomType.other:
        return l10n.roomTypeOther;
    }
  }
}