import { useState } from "react";
import { Card, Segmented, Switch } from "../components/ui";
import { IconRefresh } from "../icons";

export type Theme = "system" | "light" | "dark";

export function Settings({ theme, setTheme, version }: { theme: Theme; setTheme: (t: Theme) => void; version: string }) {
  const [sleep, setSleep] = useState(true);
  return (
    <div className="cols">
      <div className="stack">
        <Card title="Внешний вид">
          <Segmented label="Тема" value={theme} onChange={setTheme}
            options={[{ value: "system", label: "Системная" }, { value: "light", label: "Светлая" }, { value: "dark", label: "Тёмная" }]} />
        </Card>
        <Card title="Выгрузка">
          <div className="setting"><div><div>Не давать компьютеру засыпать</div><div className="hint">Только во время активной выгрузки</div></div><Switch checked={sleep} onChange={setSleep} label="Не давать засыпать" /></div>
        </Card>
      </div>
      <div className="stack">
        <Card title="Instagram"><div className="setting"><div><div>Сессия</div><div className="hint">Вход выполнен</div></div><button className="btn sm">Проверить</button></div></Card>
        <Card title="Обновления"><div className="setting"><div><div>SaveMe {version}</div><div className="hint">Вы используете последнюю версию</div></div><button className="btn sm"><IconRefresh size={16} /> Проверить</button></div></Card>
      </div>
    </div>
  );
}
