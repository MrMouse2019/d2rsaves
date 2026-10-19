using System.Text.Json.Serialization;
using D2SSharp.IO;

namespace D2SSharp.Model;

/// <summary>
/// Base class for quality-specific item data.
/// The item's Quality property determines which subclass is used.
/// </summary>
[JsonDerivedType(typeof(InferiorQualityData), "Inferior")]
[JsonDerivedType(typeof(SuperiorQualityData), "Superior")]
[JsonDerivedType(typeof(MagicQualityData), "Magic")]
[JsonDerivedType(typeof(SetUniqueQualityData), "SetUnique")]
[JsonDerivedType(typeof(RareCraftQualityData), "RareCraft")]
[JsonDerivedType(typeof(TemperedQualityData), "Tempered")]
[JsonDerivedType(typeof(NormalCharmQualityData), "NormalCharm")]
[JsonDerivedType(typeof(NormalBodyPartQualityData), "NormalBodyPart")]
[JsonDerivedType(typeof(NormalScrollBookQualityData), "NormalScrollBook")]
public abstract partial class ItemQualityData
{
    /// <summary>
    /// Gets the file index for this quality type, if applicable.
    /// Returns null for quality types that don't have a file index (Magic, Rare, Craft, Tempered, Charm, ScrollBook).
    /// </summary>
    public ushort? FileIndex => this switch
    {
        InferiorQualityData inferior => inferior.InferiorFileIndex,
        SuperiorQualityData superior => superior.SuperiorFileIndex,
        SetUniqueQualityData setUnique => setUnique.SetUniqueFileIndex,
        NormalBodyPartQualityData bodyPart => bodyPart.BodyPartFileIndex,
        _ => null
    };

    /// <summary>Writes the quality data to a BitWriter.</summary>
    /// <param name="writer">The BitWriter to write to.</param>
    /// <param name="magicPrefixOffset">Magic prefix ID offset from external data (applied to prefixes only).</param>
    public abstract void Write(ref BitWriter writer, int magicPrefixOffset = 0);
}

/// <summary>
/// Inferior (low quality) item data.
/// </summary>
public partial class InferiorQualityData : ItemQualityData
{
    /// <summary>Low quality type file index (0-7).</summary>
    public byte InferiorFileIndex { get; set; }

    public static InferiorQualityData Read(ref BitReader reader)
    {
        return new InferiorQualityData
        {
            InferiorFileIndex = (byte)reader.ReadBits(3)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: clamps to 0-7 (3 bits)
        writer.WriteBits(Math.Clamp(InferiorFileIndex, (byte)0, (byte)7), 3);
    }
}

/// <summary>
/// Superior (high quality) item data.
/// </summary>
public partial class SuperiorQualityData : ItemQualityData
{
    /// <summary>Superior type file index (0-7).</summary>
    public byte SuperiorFileIndex { get; set; }

    public static SuperiorQualityData Read(ref BitReader reader)
    {
        return new SuperiorQualityData
        {
            SuperiorFileIndex = (byte)reader.ReadBits(3)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: clamps to 0-7 (3 bits)
        writer.WriteBits(Math.Clamp(SuperiorFileIndex, (byte)0, (byte)7), 3);
    }
}

/// <summary>
/// Magic item affix data.
/// </summary>
public partial class MagicQualityData : ItemQualityData
{
    /// <summary>Magic prefix ID (0 = no prefix). Includes MagicPrefixOffset.</summary>
    public ushort PrefixId { get; set; }

    /// <summary>Magic suffix ID (0 = no suffix).</summary>
    public ushort SuffixId { get; set; }

    /// <summary>
    /// Reads magic quality data from a BitReader.
    /// </summary>
    /// <param name="reader">The BitReader to read from.</param>
    /// <param name="magicPrefixOffset">Magic prefix ID offset to add to raw prefix value.</param>
    public static MagicQualityData Read(ref BitReader reader, int magicPrefixOffset = 0)
    {
        // C++: Reads raw prefix, then adds offset if non-zero
        ushort rawPrefix = (ushort)reader.ReadBits(11);
        ushort prefixId = rawPrefix != 0 ? (ushort)(rawPrefix + magicPrefixOffset) : (ushort)0;

        return new MagicQualityData
        {
            PrefixId = prefixId,
            SuffixId = (ushort)reader.ReadBits(11)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: Subtracts offset from prefix before writing (if prefix > offset)
        int rawPrefix = PrefixId > magicPrefixOffset ? PrefixId - magicPrefixOffset : PrefixId;
        // C++: clamps to 0-2047 (11 bits)
        rawPrefix = Math.Clamp(rawPrefix, 0, 2047);

        writer.WriteBits((uint)rawPrefix, 11);
        // C++: clamps suffix to 0-2047 (11 bits)
        writer.WriteBits(Math.Clamp(SuffixId, (ushort)0, (ushort)2047), 11);
    }
}

/// <summary>
/// Set or Unique item data (same format for both).
/// </summary>
public partial class SetUniqueQualityData : ItemQualityData
{
    /// <summary>Set or Unique item file index (0-4095).</summary>
    public ushort SetUniqueFileIndex { get; set; }

    public static SetUniqueQualityData Read(ref BitReader reader)
    {
        return new SetUniqueQualityData
        {
            SetUniqueFileIndex = (ushort)reader.ReadBits(12)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: clamps to 0-4095 (12 bits), also handles negative as 4095
        writer.WriteBits(Math.Clamp(SetUniqueFileIndex, (ushort)0, (ushort)4095), 12);
    }
}

/// <summary>
/// Rare or Crafted item affix data (same format for both).
/// Note: For save files (version 96), rare names are ALWAYS present.
/// C++ uses condition: (bServer || identified), and bServer=TRUE for save files.
/// </summary>
public partial class RareCraftQualityData : ItemQualityData
{
    /// <summary>Rare name prefix ID.</summary>
    public byte RarePrefixId { get; set; }

    /// <summary>Rare name suffix ID.</summary>
    public byte RareSuffixId { get; set; }

    /// <summary>Up to 3 prefix IDs (0 = unused). Includes MagicPrefixOffset.</summary>
    public ushort[] Prefixes { get; set; } = new ushort[3];

    /// <summary>Up to 3 suffix IDs (0 = unused).</summary>
    public ushort[] Suffixes { get; set; } = new ushort[3];

    /// <summary>
    /// Reads rare/craft quality data from a BitReader.
    /// </summary>
    /// <param name="reader">The BitReader to read from.</param>
    /// <param name="magicPrefixOffset">Magic prefix ID offset to add to raw prefix values.</param>
    public static RareCraftQualityData Read(ref BitReader reader, int magicPrefixOffset = 0)
    {
        var data = new RareCraftQualityData();

        // Rare name prefix/suffix - always present in save files (bServer=TRUE)
        data.RarePrefixId = (byte)reader.ReadBits(8);
        data.RareSuffixId = (byte)reader.ReadBits(8);

        // Affix pairs are ALWAYS read regardless of identification
        for (int i = 0; i < 3; i++)
        {
            bool hasPrefix = reader.ReadBool();
            if (hasPrefix)
            {
                // C++: Reads raw prefix, then adds offset if non-zero
                ushort rawPrefix = (ushort)reader.ReadBits(11);
                data.Prefixes[i] = rawPrefix != 0 ? (ushort)(rawPrefix + magicPrefixOffset) : (ushort)0;
            }

            bool hasSuffix = reader.ReadBool();
            if (hasSuffix)
            {
                data.Suffixes[i] = (ushort)reader.ReadBits(11);
            }
        }

        return data;
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // Rare name prefix/suffix - always written for save files
        writer.WriteBits(RarePrefixId, 8);
        writer.WriteBits(RareSuffixId, 8);

        // Affix pairs are ALWAYS written
        for (int i = 0; i < 3; i++)
        {
            bool hasPrefix = Prefixes[i] != 0;
            writer.WriteBool(hasPrefix);
            if (hasPrefix)
            {
                // C++: Subtracts offset from prefix before writing (if prefix > offset)
                int rawPrefix = Prefixes[i] > magicPrefixOffset ? Prefixes[i] - magicPrefixOffset : Prefixes[i];
                // C++: clamps to 0-2047 (11 bits)
                rawPrefix = Math.Clamp(rawPrefix, 0, 2047);
                writer.WriteBits((uint)rawPrefix, 11);
            }

            bool hasSuffix = Suffixes[i] != 0;
            writer.WriteBool(hasSuffix);
            if (hasSuffix)
            {
                // C++: clamps suffix to 0-2047 (11 bits)
                writer.WriteBits(Math.Clamp(Suffixes[i], (ushort)0, (ushort)2047), 11);
            }
        }
    }
}

/// <summary>
/// Tempered item data.
/// </summary>
public partial class TemperedQualityData : ItemQualityData
{
    /// <summary>Rare name prefix ID.</summary>
    public byte RarePrefixId { get; set; }

    /// <summary>Rare name suffix ID.</summary>
    public byte RareSuffixId { get; set; }

    public static TemperedQualityData Read(ref BitReader reader)
    {
        return new TemperedQualityData
        {
            RarePrefixId = (byte)reader.ReadBits(8),
            RareSuffixId = (byte)reader.ReadBits(8)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        writer.WriteBits(RarePrefixId, 8);
        writer.WriteBits(RareSuffixId, 8);
    }
}

/// <summary>
/// Normal quality charm data.
/// C++: Charms can have a magic prefix OR suffix stored in a special format.
/// </summary>
public partial class NormalCharmQualityData : ItemQualityData
{
    /// <summary>Whether charm has a prefix (true) or suffix (false).</summary>
    public bool HasPrefix { get; set; }

    /// <summary>Magic prefix ID (if HasPrefix is true). Includes MagicPrefixOffset.</summary>
    public ushort PrefixId { get; set; }

    /// <summary>Magic suffix ID (if HasPrefix is false).</summary>
    public ushort SuffixId { get; set; }

    /// <summary>
    /// Reads normal charm quality data from a BitReader.
    /// </summary>
    /// <param name="reader">The BitReader to read from.</param>
    /// <param name="magicPrefixOffset">Magic prefix ID offset to add to raw prefix value.</param>
    public static NormalCharmQualityData Read(ref BitReader reader, int magicPrefixOffset = 0)
    {
        var data = new NormalCharmQualityData();
        data.HasPrefix = reader.ReadBool();

        if (data.HasPrefix)
        {
            // C++: Reads raw prefix, then adds offset if non-zero
            ushort rawPrefix = (ushort)reader.ReadBits(11);
            data.PrefixId = rawPrefix != 0 ? (ushort)(rawPrefix + magicPrefixOffset) : (ushort)0;
        }
        else
        {
            data.SuffixId = (ushort)reader.ReadBits(11);
        }

        return data;
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        writer.WriteBool(HasPrefix);
        if (HasPrefix)
        {
            // C++: Subtracts offset from prefix before writing (if prefix > offset)
            int rawPrefix = PrefixId > magicPrefixOffset ? PrefixId - magicPrefixOffset : PrefixId;
            // C++: clamps to 0-2047 (11 bits)
            rawPrefix = Math.Clamp(rawPrefix, 0, 2047);
            writer.WriteBits((uint)rawPrefix, 11);
        }
        else
        {
            // C++: clamps suffix to 0-2047 (11 bits)
            writer.WriteBits(Math.Clamp(SuffixId, (ushort)0, (ushort)2047), 11);
        }
    }
}

/// <summary>
/// Normal quality monster body part data.
/// C++: Body parts (non-player) have a file index.
/// </summary>
public partial class NormalBodyPartQualityData : ItemQualityData
{
    /// <summary>Monster ID file index (0-1023).</summary>
    public ushort BodyPartFileIndex { get; set; }

    public static NormalBodyPartQualityData Read(ref BitReader reader)
    {
        return new NormalBodyPartQualityData
        {
            BodyPartFileIndex = (ushort)reader.ReadBits(10)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: clamps to 0-1023 (10 bits)
        writer.WriteBits(Math.Clamp(BodyPartFileIndex, (ushort)0, (ushort)1023), 10);
    }
}

/// <summary>
/// Normal quality scroll or book data.
/// C++: Scrolls and books store the spell type in wMagicSuffix[0].
/// </summary>
public partial class NormalScrollBookQualityData : ItemQualityData
{
    /// <summary>Spell type (0-31).</summary>
    public byte SpellType { get; set; }

    public static NormalScrollBookQualityData Read(ref BitReader reader)
    {
        return new NormalScrollBookQualityData
        {
            SpellType = (byte)reader.ReadBits(5)
        };
    }

    public override void Write(ref BitWriter writer, int magicPrefixOffset = 0)
    {
        // C++: clamps to 0-31 (5 bits)
        writer.WriteBits(Math.Clamp(SpellType, (byte)0, (byte)31), 5);
    }
}
