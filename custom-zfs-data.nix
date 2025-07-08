{...}: {
  # Custom ZFS configuration for data pools only (skarabox manages root pool)

  disko.devices = {
    disk = {
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
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file:///tmp/zdata_passphrase";
        };
        postCreateHook = ''
          zfs set keylocation="file:///persist/zdata_passphrase" zdata
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
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file:///tmp/zprivate_passphrase";
        };
        postCreateHook = ''
          zfs set keylocation="file:///persist/zprivate_passphrase" zprivate
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
          nextcloud = {
            type = "zfs_fs";
            mountpoint = "/mnt/zprivate/nextcloud";
            options = {
              recordsize = "16K"; # Optimized for Nextcloud files
            };
          };
          postgresql = {
            type = "zfs_fs";
            mountpoint = "/mnt/zprivate/postgresql";
            options = {
              recordsize = "8K"; # Optimized for database
            };
            # Copy passphrases to persistent storage (moved to last dataset)
            postMountHook = ''
              # Mount the persist dataset if not already mounted
              if [ ! -d /mnt/persist ]; then
                echo "Creating /mnt/persist and mounting root/safe/persist dataset"
                mkdir -p /mnt/persist
                mount -t zfs root/safe/persist /mnt/persist
              fi

              # Copy custom ZFS pool passphrases to persistent storage
              cp /tmp/zdata_passphrase /mnt/persist/zdata_passphrase
              cp /tmp/zprivate_passphrase /mnt/persist/zprivate_passphrase
              echo "Custom ZFS pool passphrases copied to /mnt/persist"
            '';
          };
        };
      };
    };
  };
}
