import QtQuick
import qs

// бар: столбик у левого края, строка сверху (Theme.state.barAt); по центру поперёк. columns/rows ≤ 0 — Grid считает сам.
// Отдельным файлом, не inline component: новый inline component ломает горячую перезагрузку («is not a type») до рестарта qs.
// ponytail: при смене края columns и rows меняются по очереди — по разу на Pile «more visible items than rows*columns» в лог, безвредно
Grid {
    readonly property bool vert: Theme.state.barAt !== "top"
    columns: vert ? 1 : -1
    rows: vert ? -1 : 1
    horizontalItemAlignment: Grid.AlignHCenter
    verticalItemAlignment: Grid.AlignVCenter
}
