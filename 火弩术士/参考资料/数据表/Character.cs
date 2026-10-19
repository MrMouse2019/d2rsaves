using D2SSharp.Enums;
using D2SSharp.IO;

namespace D2SSharp.Model;

/// <summary>
/// Character section. v&lt;=103: 319 bytes. v>=104: 387 bytes (no Name, larger PreviewData).
/// </summary>
public partial class Character
{
    /// <summary>Section size in bytes for v&lt;=103.</summary>
    public const int SizeV103 = 319;

    /// <summary>Section size in bytes for v>=104.</summary>
    public const int SizeV104 = 387;

    /// <summary>Active weapon set (bit 0).</summary>
    public uint WeaponSwitch { get; set; }

    /// <summary>Character name (max 15 chars + null). Not serialized in v>=104.</summary>
    public string Name { get; set; } = "";

    /// <summary>Character save flags.</summary>
    public CharacterFlags Flags { get; set; }

    /// <summary>Character class.</summary>
    public CharacterClass Class { get; set; }

    /// <summary>Number of stats (always 16).</summary>
    public byte NumStats { get; set; } = 16;

    /// <summary>Number of skills per class.</summary>
    public byte NumSkills { get; set; } = 30;

    /// <summary>Character level.</summary>
    public byte Level { get; set; } = 1;

    /// <summary>Creation timestamp.</summary>
    public uint CreateTime { get; set; }

    /// <summary>Last save timestamp.</summary>
    public uint LastSaveTime { get; set; }

    /// <summary>Total play time (set to -1).</summary>
    public uint PlayTime { get; set; } = 0xFFFFFFFF;

    /// <summary>Skill hotkey assignments (16 slots).</summary>
    public Skill[] SkillHotkeys { get; set; } = new Skill[16];

    /// <summary>Left mouse button skill.</summary>
    public Skill LeftSkill { get; set; } = new();

    /// <summary>Right mouse button skill.</summary>
    public Skill RightSkill { get; set; } = new();

    /// <summary>Switch left mouse button skill.</summary>
    public Skill SwitchLeftSkill { get; set; } = new();

    /// <summary>Switch right mouse button skill.</summary>
    public Skill SwitchRightSkill { get; set; } = new();

    /// <summary>Character appearance graphics (16 bytes at offset 0x88).</summary>
    /// <remarks>C++ initializes to 0xFF, then fills from inventory via INVENTORY_GetItemSaveGfxInfo.</remarks>
    public byte[] AppearanceGraphics { get; set; } = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

    /// <summary>Character appearance tints/colors (16 bytes at offset 0x98).</summary>
    /// <remarks>C++ initializes to 0xFF, then fills from inventory via INVENTORY_GetItemSaveGfxInfo.</remarks>
    public byte[] AppearanceTints { get; set; } = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];

    /// <summary>Current town per difficulty (Normal, NM, Hell).</summary>
    public byte[] TownDifficulty { get; set; } = new byte[3];

    /// <summary>Map random seed.</summary>
    public uint MapSeed { get; set; }

    /// <summary>Mercenary data.</summary>
    public MercData MercData { get; set; } = new();

    /// <summary>Character preview data, contains UTF8 name.</summary>
    public PreviewData Preview { get; set; } = new();

    /// <summary>
    /// Gets the character section size for the given save version.
    /// </summary>
    public static int GetSize(uint saveVersion) => saveVersion >= 104 ? SizeV104 : SizeV103;

    /// <summary>
    /// Reads character data from a BitReader.
    /// </summary>
    public static Character Read(ref BitReader reader, uint saveVersion)
    {
        var data = new Character();

        data.WeaponSwitch = reader.ReadUInt32();

        // Name field only present in v<=103
        if (saveVersion < 104)
            data.Name = reader.ReadFixedString(16);

        data.Flags = (CharacterFlags)reader.ReadUInt32();
        data.Class = (CharacterClass)reader.ReadByte();
        data.NumStats = reader.ReadByte();
        data.NumSkills = reader.ReadByte();
        data.Level = reader.ReadByte();
        data.CreateTime = reader.ReadUInt32();
        data.LastSaveTime = reader.ReadUInt32();
        data.PlayTime = reader.ReadUInt32();

        // Skill hotkeys (16 * 4 bytes = 64 bytes)
        for (int i = 0; i < 16; i++)
        {
            data.SkillHotkeys[i] = Skill.Read(ref reader);
        }

        data.LeftSkill = Skill.Read(ref reader);
        data.RightSkill = Skill.Read(ref reader);
        data.SwitchLeftSkill = Skill.Read(ref reader);
        data.SwitchRightSkill = Skill.Read(ref reader);

        reader.ReadBytes(data.AppearanceGraphics);
        reader.ReadBytes(data.AppearanceTints);
        reader.ReadBytes(data.TownDifficulty);

        data.MapSeed = reader.ReadUInt32();
        data.MercData = MercData.Read(ref reader);
        data.Preview = PreviewData.Read(ref reader, saveVersion);

        return data;
    }

    /// <summary>
    /// Writes character data to a BitWriter.
    /// </summary>
    public void Write(ref BitWriter writer, uint saveVersion)
    {
        writer.WriteUInt32(WeaponSwitch);

        // Name field only present in v<=103
        if (saveVersion < 104)
            writer.WriteFixedString(Name, 16);

        writer.WriteUInt32((uint)Flags);
        writer.WriteByte((byte)Class);
        writer.WriteByte(NumStats);
        writer.WriteByte(NumSkills);
        writer.WriteByte(Level);
        writer.WriteUInt32(CreateTime);
        writer.WriteUInt32(LastSaveTime);
        writer.WriteUInt32(PlayTime);

        for (int i = 0; i < 16; i++)
        {
            SkillHotkeys[i].Write(ref writer);
        }

        LeftSkill.Write(ref writer);
        RightSkill.Write(ref writer);
        SwitchLeftSkill.Write(ref writer);
        SwitchRightSkill.Write(ref writer);

        writer.WriteBytes(AppearanceGraphics);
        writer.WriteBytes(AppearanceTints);
        writer.WriteBytes(TownDifficulty);

        writer.WriteUInt32(MapSeed);
        MercData.Write(ref writer);
        Preview.Write(ref writer, saveVersion);
    }
}
