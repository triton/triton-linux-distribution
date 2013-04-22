{ config, pkgs, ... }:

with pkgs.lib;

{
  options = {

    time = {

      timeZone = mkOption {
        default = "CET";
        type = with types; uniq string;
        example = "America/New_York";
        description = "The time zone used when displaying times and dates.";
      };

      hardwareClockInLocalTime = mkOption {
        default = false;
        description = "If set, keep the hardware clock in local time instead of UTC.";
      };

    };
  };

  config = {

    environment.shellInit =
      ''
        export TZDIR=/etc/zoneinfo
      '';

    environment.etc.localtime.source = "${pkgs.tzdata}/share/zoneinfo/${config.time.timeZone}";

    environment.etc.zoneinfo.source = "${pkgs.tzdata}/share/zoneinfo";

  };

}
