{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.logstash;

  listToConfig = list: "[ " + (concatStringsSep ", " (map exprToConfig list)) + " ]";

  hashToConfig = attrs:
    let
      attrNameToConfigList = name:
        [ (exprToConfig name)  (exprToConfig (getAttr name attrs)) ];
    in
      "[ " +
      (concatStringsSep ", " (map attrNameToConfigList (attrNames attrs))) +
      " ]";

  valueToConfig = name: value: 
    if (isAttrs value) && ((!(value ? __type)) || value.__type == "repeated")
      then ''
        ${name} {
          ${exprToConfig value}
        }
      ''
      else "${name} => ${exprToConfig value}";

  repeatedAttrsToConfig = names: values:
      concatStringsSep "\n" (zipListsWith valueToConfig names values);

  attrsToConfig = attrs:
    let
      attrToConfig = name: valueToConfig name (getAttr name attrs);
    in
      concatStringsSep "\n" (map attrToConfig (attrNames attrs));

  exprToConfig = expr:
    let
      isCustomType = expr: (isAttrs expr) && (expr ? __type);

      isFloat = expr: (isCustomType expr) && (expr.__type == "float");

      isHash = expr: (isCustomType expr) && (expr.__type == "hash");

      isRepeatedAttrs = expr: (isCustomType expr) && (expr.__type == "repeated");
    in
      if builtins.isBool expr then (if expr then "true" else "false") else
      if builtins.isString expr then ''"${expr}"'' else
      if builtins.isInt expr then toString expr else
      if isFloat expr then expr.value else
      if isList expr then listToConfig expr else
      if isHash expr then hashToConfig expr.value else
      if isRepeatedAttrs expr then repeatedAttrsToConfig expr.names expr.values
      else attrsToConfig expr;

  mergeConfigs = configs:
    let
      op = attrs: newAttrs:
        let
          isRepeated = newAttrs ? __type && newAttrs.__type == "repeated";
        in {
            names = attrs.names ++
              (if isRepeated then newAttrs.names else attrNames newAttrs);

            values = attrs.values ++
              (if isRepeated then newAttrs.values else attrValues newAttrs);
          };
    in (foldl op { names = []; values = []; } configs) //
      { __type = "repeated"; };

in

{
  ###### interface

  options = {
    services.logstash = {
      enable = mkOption {
        default = false;
        description = ''
          Enable logstash.
        '';
      };

      inputConfig = mkOption {
        default = {};
        description = ''
          An attr set representing a logstash configuration's input section.
          logstash configs are name-value pairs, where values can be bools,
          strings, numbers, arrays, hashes, or other name-value pairs,
          and names are strings that can be repeated. name-value pairs with no
          repeats are represented by attr sets. name-value pairs with repeats
          are represented by an attrset with attr "__type" = "repeated" and
          attrs "names" and "values" as matching lists pairing name and value.
          bools, strings, ints, and arrays are mapped directly. Floats are
          represented as an attrset with attr "__type" = "float" and attr value
          set to the string representation of the float. Hashes are represented
          with attr "__type" = "hash" and attr value set to an attr set
          corresponding to the hash.
        '';
        merge = mergeConfigs;
      };

      filterConfig = mkOption {
        default = {};
        description = ''
          An attr set representing a logstash configuration's filter section.
          See inputConfig description for details.
        '';
        merge = mergeConfigs;
      };

      outputConfig = mkOption {
        default = {};
        description = ''
          An attr set representing a logstash configuration's output section.
          See inputConfig description for details.
        '';
        merge = mergeConfigs;
      };
    };
  };


  ###### implementation

  config = mkIf cfg.enable {
    # Always log to stdout
    services.logstash.outputConfig = { stdout = {}; };

    jobs.logstash = with pkgs; {
      description = "Logstash daemon";

      path = [ jre ];

      exec = "java -jar ${logstash} agent -f ${writeText "logstash.conf" ''
        input {
          ${exprToConfig cfg.inputConfig}
        }

        filter {
          ${exprToConfig cfg.filterConfig}
        }

        output {
          ${exprToConfig cfg.outputConfig}
        }
      ''}";
    };
  };
}
