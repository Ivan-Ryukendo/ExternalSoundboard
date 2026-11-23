import { definePluginSettings } from "@api/Settings";
import ErrorBoundary from "@components/ErrorBoundary";
import { Heading } from "@components/Heading";
import { Paragraph } from "@components/Paragraph";
import { OptionType } from "@utils/types";
import { MediaEngineStore, Select, useEffect, useState, useStateFromStores } from "@webpack/common";

const AUTO: string = "";

export function useOutputNames() {
    const [names, setNames] = useState<string[]>([]);
    useEffect(() => {
        navigator.mediaDevices.enumerateDevices().then(d => setNames(
            d.filter(x => x.kind === "audiooutput" && x.deviceId !== "default" && x.deviceId !== "communications").map(x => x.label)
        ));
    }, []);
    return names;
}

function DeviceSelect({ title, description, autoLabel, names, value, onChange }: {
    title: string; description: string; autoLabel: string; names: string[]; value: string; onChange(v: string): void;
}) {
    const options = [{ label: autoLabel, value: AUTO }, ...names.map(n => ({ label: n, value: n }))];
    return (
        <div style={{ marginBottom: 16 }}>
            <Heading>{title}</Heading>
            <Paragraph>{description}</Paragraph>
            <Select
                options={options}
                maxVisibleItems={6}
                closeOnSelect
                select={onChange}
                isSelected={v => v === value}
                serialize={String}
            />
        </div>
    );
}

const inputSetting = (key: "loopbackInput" | "micInput", title: string, description: string, autoLabel: string) => ({
    type: OptionType.COMPONENT,
    default: AUTO,
    component: ErrorBoundary.wrap(({ setValue }: { setValue(v: string): void; }) => {
        const inputs = useStateFromStores([MediaEngineStore], () => Object.values(MediaEngineStore.getInputDevices()).map(d => d.name));
        return <DeviceSelect title={title} description={description} autoLabel={autoLabel} names={inputs}
            value={settings.store[key]} onChange={v => { settings.store[key] = v; setValue(v); }} />;
    }, { noop: true })
} as const);

export const settings = definePluginSettings({
    loopbackInput: inputSetting(
        "loopbackInput", "Loopback input",
        "The input that records your speakers (usually Stereo Mix).",
        "Auto-detect (Stereo Mix)"
    ),
    micInput: inputSetting(
        "micInput", "Your microphone",
        "Switched back to this after each sound.",
        "Whatever mic was active"
    ),
    playbackOutput: {
        type: OptionType.COMPONENT,
        default: AUTO,
        component: ErrorBoundary.wrap(({ setValue }: { setValue(v: string): void; }) => {
            const outputs = useOutputNames();
            return <DeviceSelect title="Playback output"
                description="The output the loopback input records. Set Discord's own output to a different device, or friends hear an echo."
                autoLabel="Auto-detect (matches loopback)" names={outputs}
                value={settings.store.playbackOutput} onChange={v => { settings.store.playbackOutput = v; setValue(v); }} />;
        }, { noop: true })
    },
    settleMs: {
        type: OptionType.NUMBER,
        description: "Wait after switching the input device, in ms",
        default: 400
    }
});
