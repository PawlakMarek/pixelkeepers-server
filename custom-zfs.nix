{
  config,
  lib,
  ...
}: {
  # Override skarabox's disko configuration for custom ZFS layout
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-PC711_NVMe_SK_hynix_1TB__AJ0CN64661240154T";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-PC711_NVMe_SK_hynix_1TB__AJ0CN64661240154R";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot-mirror";
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
        };
      };
      hdd0 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-HUH728080ALE601_VLKM123Y"; # 8TB drive
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      hdd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-HUH728080ALE601_VJG691YX"; # 8TB drive
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      hdd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-HUH728080ALE601_VLK02LMY"; # 8TB drive
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      hdd3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-ST14000NM0018-2H4101_ZHZ30WXP"; # 14TB drive
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zdata";
              };
            };
          };
        };
      };
      hdd4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Hitachi_HUS724040ALE641_PBK2KYYT"; # 4TB drive for zprivate
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zprivate";
              };
            };
          };
        };
      };
    };

    zpool = {
      root = {
        type = "zpool";
        mode = "mirror";
        rootFsOptions = {
          canmount = "off";
          checksum = "edonr";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "file:///tmp/secret.key";
        };
        postCreateHook = ''
          zfs set keylocation="prompt" zroot
        '';
        datasets = {
          reserved = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
              reservation = "500M";
            };
          };
          local = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            postCreateHook = "zfs snapshot zroot/local/root@blank";
          };
          "local/nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
          };
          safe = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
            };
          };
          "safe/home" = {
            type = "zfs_fs";
            mountpoint = "/home";
          };
          "safe/persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
          };
        };
      };

      zdata = {
        type = "zpool";
        mode = "raidz2";
        rootFsOptions = {
          canmount = "off";
          checksum = "edonr";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "file:///tmp/zdata-secret.key";
        };
        postCreateHook = ''
          zfs set keylocation="prompt" zdata
        '';
        datasets = {
          reserved = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
              reservation = "400G";
            };
          };
          media = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media";
            options = {
              recordsize = "1M"; # Optimized for large files
            };
          };
          "media/movies" = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media/movies";
          };
          "media/tv" = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media/tv";
          };
          "media/music" = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media/music";
          };
          "media/books" = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media/books";
          };
          "media/comics" = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/media/comics";
          };
          downloads = {
            type = "zfs_fs";
            mountpoint = "/mnt/zdata/downloads";
          };
        };
      };

      zprivate = {
        type = "zpool";
        mode = ""; # Single disk initially, will become mirror later
        rootFsOptions = {
          canmount = "off";
          checksum = "edonr";
          compression = "lz4";
          dnodesize = "auto";
          mountpoint = "none";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "file:///tmp/zprivate-secret.key";
        };
        postCreateHook = ''
          zfs set keylocation="prompt" zprivate
        '';
        datasets = {
          reserved = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              mountpoint = "none";
              reservation = "200G"; # 5% of 4TB
            };
          };
          documents = {
            type = "zfs_fs";
            mountpoint = "/mnt/zprivate/documents";
          };
          pictures = {
            type = "zfs_fs";
            mountpoint = "/mnt/zprivate/pictures";
            options = {
              recordsize = "16K"; # Optimized for photos
            };
          };
          backups = {
            type = "zfs_fs";
            mountpoint = "/mnt/zprivate/backups";
          };
        };
      };
    };
  };
}
